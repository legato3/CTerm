// Tab+InlineSession.swift
// CTerm
//
// Per-tab helpers that mutate the tab's inline AgentSession. These replace the
// prior Tab+OllamaAgentSession extension (which mutated a value-type struct).
// Each method creates or updates an AgentSession(kind: .inline) and registers
// it with AgentSessionRouter so all sessions flow through one factory.

import Foundation

@MainActor
extension Tab {

    func startOllamaAgent(goal: String, rawPrompt: String, backend: AgentPlanningBackend) {
        let backendValue: AgentBackend = (backend == .claudeSubscription) ? .claudeSubscription : .ollama
        let session = AgentSessionRouter.shared.start(
            AgentSessionRequest(
                intent: goal,
                kind: .inline,
                backend: backendValue,
                tabID: id,
                pwd: pwd,
                preEnrichedPrompt: rawPrompt
            ),
            activeTab: self
        )
        session.inlineSteps = [InlineAgentStep(kind: .goal, text: goal)]
        session.transition(to: .thinking)
        ollamaAgentSession = session
    }

    func updateOllamaAgentPlanPreview(_ text: String) {
        guard let session = ollamaAgentSession else { return }
        session.pendingMessage = text
        session.transition(to: .thinking)
    }

    func setOllamaAgentAwaitingApproval(command: String, message: String) {
        guard let session = ollamaAgentSession else { return }
        session.pendingCommand = command
        session.pendingMessage = message
        session.inlineSteps.insert(
            InlineAgentStep(kind: .plan, text: message, command: command),
            at: 0
        )
        session.transition(to: .awaitingApproval)
    }

    func markOllamaAgentRunning(blockID: UUID?) {
        guard let session = ollamaAgentSession else { return }
        let command = session.pendingCommand
        let message = session.pendingMessage
        session.lastCommandBlockID = blockID
        session.inlineIteration += 1
        session.pendingCommand = nil
        session.pendingMessage = nil
        if let command {
            session.inlineSteps.insert(
                InlineAgentStep(kind: .command, text: message ?? command, command: command),
                at: 0
            )
        }
        session.transition(to: .running)
    }

    func recordOllamaAgentObservation(_ text: String) {
        guard let session = ollamaAgentSession else { return }
        session.inlineSteps.insert(InlineAgentStep(kind: .observation, text: text), at: 0)
    }

    func completeOllamaAgent(summary: String) {
        guard let session = ollamaAgentSession else { return }
        session.pendingCommand = nil
        session.pendingMessage = summary
        session.inlineSteps.insert(InlineAgentStep(kind: .summary, text: summary), at: 0)
        session.summary = summary
        session.transition(to: .completed)
    }

    func failOllamaAgent(_ message: String) {
        guard let session = ollamaAgentSession else { return }
        session.pendingCommand = nil
        session.pendingMessage = message
        session.inlineSteps.insert(InlineAgentStep(kind: .error, text: message), at: 0)
        session.fail(message: message)
    }

    func stopOllamaAgent() {
        guard let session = ollamaAgentSession else { return }
        session.pendingCommand = nil
        session.pendingMessage = "Agent stopped."
        session.cancel()
    }
}
