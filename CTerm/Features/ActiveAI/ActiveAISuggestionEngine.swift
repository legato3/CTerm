// ActiveAISuggestionEngine.swift
// CTerm
//
// Unified suggestion coordinator. Single output channel: the chip bar.
// Merges what was previously three separate surfaces (suggestion chips,
// ghost text predictions, ambient suggestions) into one ranked list.
// Max 2 chips visible at a time. No telemetry logging.

import Foundation
import OSLog
import Observation

private let logger = Logger(subsystem: "com.legato3.cterm", category: "ActiveAI")

// MARK: - Model

struct ActiveAISuggestion: Identifiable, Sendable {
    let id: UUID
    let prompt: String
    let icon: String
    let kind: Kind
    let blockID: UUID?
    let confidence: Double

    enum Kind: Sendable {
        case fix
        case explain
        case nextStep
        case continueAgent
        case custom(String)
    }

    init(prompt: String, icon: String, kind: Kind, blockID: UUID? = nil, confidence: Double = 0.5) {
        self.id = UUID()
        self.prompt = prompt
        self.icon = icon
        self.kind = kind
        self.blockID = blockID
        self.confidence = confidence
    }
}

// MARK: - Engine

@Observable
@MainActor
final class ActiveAISuggestionEngine: AgentSessionObserver {

    /// Current suggestions. Single output channel — max 2 visible.
    private(set) var suggestions: [ActiveAISuggestion] = []
    /// True while generating suggestions.
    private(set) var isGenerating = false

    private var generationTask: Task<Void, Never>?
    private var lastBlockID: UUID?
    private var planObserver: NSObjectProtocol?
    private var sessionObserver: NSObjectProtocol?

    /// Recent command blocks for context (set by the window controller).
    var recentBlocks: [TerminalCommandBlock] = []

    /// Max visible chips — reduced from 3 to 2 for less noise.
    static let maxVisibleChips = 2

    // MARK: - Lifecycle

    func startObserving() {
        guard planObserver == nil else { return }
        planObserver = NotificationCenter.default.addObserver(
            forName: .agentPlanCompleted,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let goal = note.userInfo?["goal"] as? String ?? "the previous task"
            Task { @MainActor [weak self] in
                guard let self else { return }
                let chip = ActiveAISuggestion(
                    prompt: "Continue from: \(goal)",
                    icon: "arrow.right.circle.fill",
                    kind: .continueAgent,
                    confidence: 0.7
                )
                self.injectSuggestion(chip)
            }
        }

        guard sessionObserver == nil else { return }
        sessionObserver = NotificationCenter.default.addObserver(
            forName: .agentSessionCompleted,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let nextActions = note.userInfo?["nextActions"] as? [String] ?? []
            Task { @MainActor [weak self] in
                guard let self else { return }
                for action in nextActions.prefix(2) {
                    guard !ConfidenceScorer.isGenericSuggestion(action) else { continue }
                    self.injectSuggestion(ActiveAISuggestion(
                        prompt: action,
                        icon: "arrow.right.circle",
                        kind: .nextStep,
                        confidence: 0.55
                    ))
                }
            }
        }
    }

    func stopObserving() {
        if let observer = planObserver {
            NotificationCenter.default.removeObserver(observer)
            planObserver = nil
        }
        if let observer = sessionObserver {
            NotificationCenter.default.removeObserver(observer)
            sessionObserver = nil
        }
    }

    // MARK: - AgentSessionObserver

    /// Attach to an AgentSession so we receive phase/completion callbacks directly
    /// instead of going through NotificationCenter. Callers: AgentLoopCoordinator,
    /// future inline/queued/delegated session drivers.
    func attach(to session: AgentSession) {
        session.addObserver(self)
    }

    func session(_ session: AgentSession, didComplete result: AgentResult) {
        for action in result.nextActions.prefix(2) {
            guard !ConfidenceScorer.isGenericSuggestion(action.prompt) else { continue }
            injectSuggestion(ActiveAISuggestion(
                prompt: action.prompt,
                icon: "arrow.right.circle",
                kind: .nextStep,
                confidence: action.confidence
            ))
        }
    }

    // MARK: - Public API

    /// Called when a command block finishes. Generates contextual suggestions.
    func onBlockFinished(_ block: TerminalCommandBlock, pwd: String?) {
        guard UserDefaults.standard.bool(forKey: AppStorageKeys.activeAIEnabled) else { return }
        guard block.id != lastBlockID else { return }
        lastBlockID = block.id

        if ConfidenceScorer.isTrivialCommand(block.titleText) {
            suggestions = []
            return
        }

        let candidates = staticSuggestions(for: block)
        let hasMemory = hasRelevantMemory(pwd: pwd)
        suggestions = SuggestionFilter.filterAndRank(
            candidates,
            block: block,
            recentCommands: recentBlocks,
            hasRelevantMemory: hasMemory
        )

        // Cap to our reduced limit
        if suggestions.count > Self.maxVisibleChips {
            suggestions = Array(suggestions.prefix(Self.maxVisibleChips))
        }

        generateNextStepSuggestion(for: block, pwd: pwd)
    }

    /// Clear all suggestions.
    func clear() {
        generationTask?.cancel()
        generationTask = nil
        suggestions = []
        isGenerating = false
    }

    /// Inject a suggestion from the agent loop or other source.
    func injectSuggestion(_ suggestion: ActiveAISuggestion) {
        guard !SuggestionFilter.isDuplicate(suggestion, existingSuggestions: suggestions) else { return }
        suggestions.append(suggestion)
        if suggestions.count > Self.maxVisibleChips {
            suggestions = Array(suggestions
                .sorted { $0.confidence > $1.confidence }
                .prefix(Self.maxVisibleChips))
        }
    }

    // MARK: - Static Suggestions

    private func staticSuggestions(for block: TerminalCommandBlock) -> [ActiveAISuggestion] {
        var chips: [ActiveAISuggestion] = []

        if block.status == .failed {
            let hasActionable = block.errorSnippet.map { ConfidenceScorer.containsActionableError($0) } ?? false
            let fixConfidence: Double = hasActionable ? 0.75 : 0.5

            let fixPrompt: String
            if let snippet = block.errorSnippet, ConfidenceScorer.containsKnownErrorPattern(snippet) {
                let errorLine = snippet.components(separatedBy: "\n")
                    .first(where: { line in
                        let l = line.lowercased()
                        return l.contains("error") || l.contains("failed") || l.contains("not found")
                    }) ?? block.titleText
                fixPrompt = "Fix: \(String(errorLine.prefix(60)))"
            } else {
                fixPrompt = "Fix this error: \(block.titleText)"
            }

            chips.append(ActiveAISuggestion(
                prompt: fixPrompt,
                icon: "wrench.and.screwdriver",
                kind: .fix,
                blockID: block.id,
                confidence: fixConfidence
            ))
        } else if block.status == .succeeded {
            if let snippet = block.outputSnippet, snippet.count > 200 {
                chips.append(ActiveAISuggestion(
                    prompt: "Explain the output of: \(block.titleText)",
                    icon: "text.magnifyingglass",
                    kind: .explain,
                    blockID: block.id,
                    confidence: 0.35
                ))
            }
        }

        return chips
    }

    // MARK: - LLM Next-Step Suggestion

    private func generateNextStepSuggestion(for block: TerminalCommandBlock, pwd: String?) {
        generationTask?.cancel()
        isGenerating = true

        generationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isGenerating = false }

            let context = await TerminalContextGatherer.gather(pwd: pwd)
            let predContext = PredictionContextBuilder.build(
                blocks: self.recentBlocks,
                pwd: pwd,
                terminalContext: context
            )
            let prompt = self.buildNextStepPrompt(block: block, context: predContext)

            do {
                let suggestion = try await OllamaCommandService.generateCommand(for: prompt, pwd: pwd)
                guard !Task.isCancelled else { return }
                let trimmed = suggestion.trimmingCharacters(in: .whitespacesAndNewlines)

                guard SuggestionFilter.isLLMSuggestionWorthShowing(
                    trimmed, block: block, existingSuggestions: self.suggestions
                ) else { return }

                let hasMemory = self.hasRelevantMemory(pwd: pwd)
                let score = ConfidenceScorer.scoreSuggestion(
                    block: block,
                    suggestionText: trimmed,
                    recentCommands: self.recentBlocks,
                    hasRelevantMemory: hasMemory
                )
                guard score.isAboveLLMThreshold else { return }

                self.injectSuggestion(ActiveAISuggestion(
                    prompt: trimmed,
                    icon: "arrow.right.circle",
                    kind: .nextStep,
                    blockID: block.id,
                    confidence: score.value
                ))
            } catch {
                logger.debug("ActiveAI: suggestion generation failed: \(error.localizedDescription)")
            }
        }
    }

    private func buildNextStepPrompt(block: TerminalCommandBlock, context: PredictionContext) -> String {
        let status = block.status == .failed ? "failed (exit \(block.exitCode ?? -1))" : "succeeded"
        let snippet = block.primarySnippet.map { "\n\nOutput (last 500 chars):\n\(String($0.suffix(500)))" } ?? ""

        return """
        Based on this terminal session, suggest the single most useful next action \
        as a short natural-language prompt (max 12 words). \
        The prompt will be sent to an AI coding agent.

        Rules:
        - Be specific to the actual error or output. Reference file names, error codes, or test names.
        - Do NOT suggest generic actions like "try again", "check logs", "read docs", or "review the error".
        - If the command succeeded and the output is unremarkable, respond with just "SKIP".
        - If you're not confident, respond with just "SKIP".

        Context:
        \(context.enrichedContextBlock)

        Last command: \(block.titleText) [\(status)]\(snippet)

        Respond with only the prompt text (or "SKIP"), no explanation.
        """
    }

    // MARK: - Helpers

    private func hasRelevantMemory(pwd: String?) -> Bool {
        guard let pwd else { return false }
        let key = AgentMemoryStore.key(for: pwd)
        return !AgentMemoryStore.shared.listAll(projectKey: key).isEmpty
    }
}
