// AgentLoopCoordinator.swift
// CTerm
//
// Top-level coordinator for the agent pipeline.
// Simplified: approve the plan or don't. No batching, no denial negotiation.

import Foundation
import OSLog
import Observation

private let logger = Logger(subsystem: "com.legato3.cterm", category: "AgentLoopCoordinator")

@Observable
@MainActor
final class AgentLoopCoordinator {

    /// The active session being coordinated. Nil when idle.
    private(set) var activeSession: AgentSessionState?

    /// History of completed sessions (most recent first). Capped at 20.
    private(set) var sessionHistory: [AgentSessionState] = []

    /// Streaming plan preview text (updated during LLM plan generation).
    private(set) var streamingPreview: String?

    private let planStore: AgentPlanStore
    private let suggestionEngine: ActiveAISuggestionEngine
    private var executionCoordinator: ExecutionCoordinator?
    private var sessionObserver: NSObjectProtocol?

    init(planStore: AgentPlanStore, suggestionEngine: ActiveAISuggestionEngine) {
        self.planStore = planStore
        self.suggestionEngine = suggestionEngine
    }

    // MARK: - Pipeline Entry Point

    func startSession(
        intent: String,
        tabID: UUID? = nil,
        pwd: String?,
        activeTab: Tab? = nil
    ) async {
        if let existing = activeSession, !existing.phase.isTerminal {
            existing.transitionTo(.completed)
            archiveSession(existing)
        }

        let enrichedIntent = AgentPromptContextBuilder.buildPrompt(goal: intent, activeTab: activeTab)
        let session = AgentSessionState(userIntent: enrichedIntent, tabID: tabID)
        activeSession = session
        streamingPreview = nil

        logger.info("AgentLoop: starting session for: \(session.displayIntent.prefix(80))")

        // Classify
        session.transitionTo(.classifying)
        let (category, confidence) = IntentRouter.classify(enrichedIntent)
        if confidence < 0.4 {
            session.classifiedIntent = await IntentRouter.classifyWithLLM(intent, pwd: pwd)
        } else {
            session.classifiedIntent = category
        }
        guard !session.phase.isTerminal else { return }

        // Build plan
        PlanBuilder.onStreamingPreview = { [weak self] text in
            self?.streamingPreview = text
        }
        await PlanBuilder.buildPlan(for: session, pwd: pwd)
        streamingPreview = nil
        PlanBuilder.onStreamingPreview = nil

        guard !session.phase.isTerminal else { return }

        if session.phase == .awaitingApproval {
            logger.info("AgentLoop: plan ready, awaiting approval (\(session.planSteps.count) steps)")
            return
        }

        await executeSession(pwd: pwd)
    }

    // MARK: - Approval (simple: approve all or stop)

    func approveAndExecute(pwd: String?) async {
        guard let session = activeSession,
              session.phase == .awaitingApproval else { return }

        for i in session.planSteps.indices where session.planSteps[i].status == .pending {
            session.planSteps[i].status = .approved
        }

        NotificationCenter.default.post(
            name: .agentPlanApproved,
            object: nil,
            userInfo: [
                "goal": session.displayIntent,
                "totalSteps": session.planSteps.count,
            ]
        )

        await executeSession(pwd: pwd)
    }

    /// Skip a step by ID.
    func skipStep(id: UUID) {
        guard let session = activeSession else { return }
        if let idx = session.planSteps.firstIndex(where: { $0.id == id }) {
            session.planSteps[idx].status = .skipped
        }
    }

    // MARK: - Stop

    func stopSession() {
        guard let session = activeSession else { return }
        executionCoordinator?.stop()
        session.transitionTo(.completed)
        session.summary = "Stopped by user."
        archiveSession(session)
        activeSession = nil
    }

    // MARK: - Command Finished (from terminal)

    func handleCommandFinished(exitCode: Int, output: String?) {
        executionCoordinator?.handleCommandFinished(exitCode: exitCode, output: output)
    }

    // MARK: - Execution

    private func executeSession(pwd: String?) async {
        guard let session = activeSession else { return }

        let executor = AgentPlanExecutor(planStore: planStore)
        let coordinator = ExecutionCoordinator(
            session: session,
            planStore: planStore,
            executor: executor
        )
        self.executionCoordinator = coordinator

        coordinator.onAllStepsCompleted = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.summarizeAndSuggest(pwd: pwd)
            }
        }

        coordinator.onObservation = { [weak self] _, _ in
            guard let self, let session = self.activeSession else { return }
            let changedFiles = FileChangeStore.shared.recentPaths(limit: 5)
            for file in changedFiles {
                session.addArtifact(AgentArtifact(kind: .fileChanged, value: file))
            }
        }

        coordinator.onReplanNeeded = { failedStep, output in
            return await Self.generateReplanSteps(failedStep: failedStep, output: output, pwd: pwd)
        }

        coordinator.start()
    }

    // MARK: - Replan

    private static func generateReplanSteps(
        failedStep: AgentPlanStep,
        output: String,
        pwd: String?
    ) async -> [AgentPlanStep]? {
        let prompt = """
        A step in an agent plan failed. Generate 1-3 replacement steps to recover.
        Format each step as: "STEP: <title> | CMD: <shell command or empty>"

        Failed step: \(failedStep.title)
        Command: \(failedStep.command ?? "(none)")
        Error output: \(output.prefix(500))

        Replacement steps:
        """

        do {
            let response = try await OllamaCommandService.generateCommand(for: prompt, pwd: pwd)
            let steps = parseReplanResponse(response)
            return steps.isEmpty ? nil : steps
        } catch {
            logger.debug("AgentLoop: replan generation failed: \(error.localizedDescription)")
            return nil
        }
    }

    private static func parseReplanResponse(_ response: String) -> [AgentPlanStep] {
        let lines = response.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var steps: [AgentPlanStep] = []
        for line in lines {
            if line.uppercased().hasPrefix("STEP:") {
                let content = String(line.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
                let parts = content.components(separatedBy: " | CMD:")
                let title = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let command = parts.count > 1
                    ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    : nil
                let cmd = (command?.isEmpty == true || command == "empty") ? nil : command
                steps.append(AgentPlanStep(title: title, command: cmd))
            }
        }
        return steps
    }

    // MARK: - Summarization

    private func summarizeAndSuggest(pwd: String?) async {
        guard let session = activeSession else { return }
        await ResultSummarizer.summarize(session, pwd: pwd)
        wireSuggestionsToActiveAI(session)
        archiveSession(session)
    }

    // MARK: - ActiveAI Integration

    private func wireSuggestionsToActiveAI(_ session: AgentSessionState) {
        suggestionEngine.clear()

        let completionChip = ActiveAISuggestion(
            prompt: session.summary ?? "Session completed",
            icon: session.planSteps.contains(where: { $0.status == .failed })
                ? "exclamationmark.triangle.fill"
                : "checkmark.circle.fill",
            kind: .continueAgent
        )
        suggestionEngine.injectSuggestion(completionChip)

        for action in session.nextActions {
            suggestionEngine.injectSuggestion(ActiveAISuggestion(
                prompt: action,
                icon: "arrow.right.circle",
                kind: .nextStep
            ))
        }
    }

    // MARK: - History

    private func archiveSession(_ session: AgentSessionState) {
        sessionHistory.insert(session, at: 0)
        if sessionHistory.count > 20 {
            sessionHistory = Array(sessionHistory.prefix(20))
        }
    }
}
