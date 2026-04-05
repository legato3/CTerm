// ResultSummarizer.swift
// CTerm
//
// Produces a structured AgentResult after an agent session finishes.
// Builds the summary, captures file changes, scores next-action suggestions
// with confidence, and calls session.complete(with:) which fires the
// observer didComplete callback + posts the agentSessionCompleted notification.

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.legato3.cterm", category: "ResultSummarizer")

@MainActor
enum ResultSummarizer {

    // MARK: - Public API

    /// Summarize a completed session: constructs an AgentResult, writes the
    /// handoff to AgentMemoryStore, and fires session.complete(with:).
    static func summarize(_ session: AgentSession, pwd: String?) async {
        session.transition(to: .summarizing)

        let summary = buildSummary(session)
        let nextActions = await generateNextActions(session, pwd: pwd)
        let filesChanged = await captureFilesChanged(session, pwd: pwd)
        let durationMs = Int(session.elapsedSeconds * 1000)
        let handoffKey = persistHandoff(session, pwd: pwd)
        let exitStatus = computeExitStatus(session)

        let result = AgentResult(
            summary: summary,
            filesChanged: filesChanged,
            nextActions: nextActions,
            durationMs: durationMs,
            handoffMemoryKey: handoffKey,
            exitStatus: exitStatus
        )

        // Compat mirrors — existing consumers (sidebar, notifications) still
        // read these string-backed fields.
        session.summary = summary
        session.nextActions = nextActions.map(\.prompt)

        // Fires observer.didComplete(result:) → ActiveAISuggestionEngine
        // gets real confidence values for chip ranking.
        session.complete(with: result)

        // Back-compat notification for consumers not yet on the observer path.
        NotificationCenter.default.post(
            name: .agentSessionCompleted,
            object: nil,
            userInfo: [
                "sessionID": session.id.uuidString,
                "intent": session.displayIntent,
                "summary": summary,
                "nextActions": nextActions.map(\.prompt),
                "artifactCount": session.artifacts.count,
            ]
        )

        logger.info("ResultSummarizer: session completed (\(exitStatus.rawValue)) — \(summary.prefix(100))")
    }

    // MARK: - Exit Status

    private static func computeExitStatus(_ session: AgentSession) -> AgentResult.ExitStatus {
        if session.phase == .cancelled { return .cancelled }
        let steps = session.plan?.steps ?? []
        let failed = steps.filter { $0.status == .failed }.count
        let succeeded = steps.filter { $0.status == .succeeded }.count
        if failed > 0 && succeeded > 0 { return .partial }
        if failed > 0 { return .failed }
        if session.phase == .failed { return .failed }
        return .succeeded
    }

    // MARK: - Summary Construction

    private static func buildSummary(_ session: AgentSession) -> String {
        let total = (session.plan?.steps ?? []).count
        let succeeded = (session.plan?.steps ?? []).filter { $0.status == .succeeded }.count
        let failed = (session.plan?.steps ?? []).filter { $0.status == .failed }.count
        let skipped = (session.plan?.steps ?? []).filter { $0.status == .skipped }.count

        var parts: [String] = []

        // Intent
        parts.append("Goal: \(session.displayIntent.prefix(80))")

        // Browser research specific summary
        if session.classifiedIntent == .browserResearch {
            let browserOutputs = session.artifacts
                .filter { $0.kind == .commandOutput && $0.value.hasPrefix("Browser") }
            let findingCount = session.artifacts
                .filter { $0.kind == .browserFinding || $0.value.hasPrefix("Research summary:") }
                .count
            if findingCount > 0 {
                parts.append("\(findingCount) browser finding(s) captured")
            }
            if !browserOutputs.isEmpty {
                parts.append("Browsed \(browserOutputs.count) page(s)")
            }
        }

        // Step results
        if total > 0 {
            var stepSummary = "\(succeeded)/\(total) steps succeeded"
            if failed > 0 { stepSummary += ", \(failed) failed" }
            if skipped > 0 { stepSummary += ", \(skipped) skipped" }
            parts.append(stepSummary)
        }

        // Duration
        let duration = session.elapsedSeconds
        if duration < 60 {
            parts.append("Completed in \(Int(duration))s")
        } else {
            parts.append("Completed in \(Int(duration / 60))m \(Int(duration.truncatingRemainder(dividingBy: 60)))s")
        }

        return parts.joined(separator: ". ") + "."
    }

    // MARK: - File Changes

    private static func captureFilesChanged(_ session: AgentSession, pwd: String?) async -> [ChangedFile] {
        // Preferred: ask git directly for a structured numstat + porcelain
        // view of the working tree. This gives real add/del counts and the
        // correct status classification (added / modified / deleted / renamed
        // / untracked) that the inline diff review panel needs.
        if let pwd {
            let gitView = await ChangedFileExtractor.extract(workDir: pwd)
            if !gitView.isEmpty { return gitView }
        }

        // Fallback 1: paths the in-process FileChangeStore tracked during
        // the session. No git stats available — map to .modified with zero
        // counts so the UI still lists the files.
        let recentPaths = FileChangeStore.shared.recentPaths(limit: 20)
        if !recentPaths.isEmpty {
            return recentPaths.map {
                ChangedFile(path: $0, status: .modified, additions: 0, deletions: 0, oldPath: nil)
            }
        }

        // Fallback 2: artifacts the executor explicitly tagged as .fileChanged.
        return session.artifacts
            .filter { $0.kind == .fileChanged }
            .map { ChangedFile(path: $0.value, status: .modified, additions: 0, deletions: 0, oldPath: nil) }
    }

    // MARK: - Next Action Generation

    private static func generateNextActions(_ session: AgentSession, pwd: String?) async -> [NextAction] {
        var actions: [NextAction] = []

        let failedSteps = (session.plan?.steps ?? []).filter { $0.status == .failed }
        let hasFailed = !failedSteps.isEmpty

        if hasFailed, let failedStep = failedSteps.first {
            let snippet = failedStep.output?.prefix(120).replacingOccurrences(of: "\n", with: " ") ?? ""
            actions.append(NextAction(
                label: "Fix: \(failedStep.title.prefix(40))",
                prompt: "Fix the failure in '\(failedStep.title)'. \(snippet)",
                confidence: 0.9
            ))
            if failedSteps.count > 1 {
                actions.append(NextAction(
                    label: "Retry failed steps",
                    prompt: "Retry the \(failedSteps.count) failed steps from the previous run",
                    confidence: 0.7
                ))
            }
        } else {
            // Success path — intent-aware suggestions
            switch session.classifiedIntent {
            case .executeCommand:
                actions.append(NextAction(
                    label: "Run tests to verify",
                    prompt: "Run the test suite to verify the change",
                    confidence: 0.75
                ))
            case .fixError:
                actions.append(NextAction(
                    label: "Run tests to confirm fix",
                    prompt: "Run the test suite to confirm the fix",
                    confidence: 0.8
                ))
                actions.append(NextAction(
                    label: "Review the changes",
                    prompt: "Review the files that just changed",
                    confidence: 0.6
                ))
            case .runWorkflow:
                actions.append(NextAction(
                    label: "Review changes and commit",
                    prompt: "Review the changes and prepare a commit",
                    confidence: 0.75
                ))
            case .inspectRepo:
                actions.append(NextAction(
                    label: "Dig deeper into findings",
                    prompt: "Dig deeper into the findings from the last inspection",
                    confidence: 0.6
                ))
            case .browserResearch:
                actions.append(NextAction(
                    label: "Apply findings to codebase",
                    prompt: "Apply the research findings to the codebase",
                    confidence: 0.7
                ))
                let hasFindings = session.artifacts.contains { $0.kind == .browserFinding }
                if hasFindings {
                    actions.append(NextAction(
                        label: "Research a related topic",
                        prompt: "Research a related topic",
                        confidence: 0.5
                    ))
                }
            default:
                break
            }
        }

        // LLM-generated low-confidence next step
        if let llmSuggestion = await generateLLMNextAction(session, pwd: pwd) {
            actions.append(NextAction(
                label: String(llmSuggestion.prefix(40)),
                prompt: llmSuggestion,
                confidence: 0.5
            ))
        }

        return Array(actions.prefix(3))
    }

    private static func generateLLMNextAction(_ session: AgentSession, pwd: String?) async -> String? {
        let lastOutput = (session.plan?.steps ?? []).last(where: { $0.output != nil })?.output ?? ""
        let prompt = """
        Based on this completed task, suggest the single most useful next action as a short prompt (max 12 words).
        The prompt will be sent to an AI coding agent.

        Task: \(session.displayIntent.prefix(200))
        Outcome: \(session.summary ?? "completed")
        Last output: \(lastOutput.prefix(300))

        Respond with only the prompt text, no explanation.
        """

        do {
            let result = try await OllamaCommandService.generateCommand(for: prompt, pwd: pwd)
            let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("NOTE:"), trimmed.count < 100 else { return nil }
            return trimmed
        } catch {
            return nil
        }
    }

    // MARK: - Handoff Persistence

    @discardableResult
    private static func persistHandoff(_ session: AgentSession, pwd: String?) -> String? {
        guard let pwd else { return nil }
        let projectKey = AgentMemoryStore.key(for: pwd)

        let handoff = AgentMemoryStore.shared.saveHandoff(
            projectKey: projectKey,
            goal: session.displayIntent,
            stepsCompleted: (session.plan?.steps ?? []).filter { $0.status == .succeeded }.count,
            totalSteps: (session.plan?.steps ?? []).count,
            filesChanged: session.artifacts.filter { $0.kind == .fileChanged }.map(\.value),
            outcome: session.phase.label
        )

        // Save file changes to memory
        let changedFiles = session.artifacts.filter { $0.kind == .fileChanged }.map(\.value)
        if !changedFiles.isEmpty {
            AgentMemoryStore.shared.remember(
                projectKey: projectKey,
                key: "last_session_files",
                value: changedFiles.joined(separator: ", "),
                ttlDays: 7
            )
        }

        return handoff.key
    }
}

// MARK: - Notification

extension Notification.Name {
    static let agentSessionCompleted = Notification.Name("com.legato3.cterm.agentSessionCompleted")
}
