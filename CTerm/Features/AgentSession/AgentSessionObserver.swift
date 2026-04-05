// AgentSessionObserver.swift
// CTerm
//
// Protocol observers use to subscribe to AgentSession lifecycle events.
// Replaces the NotificationCenter-based wiring between sessions and consumers
// (ActiveAISuggestionEngine, IPCAgentState, AgentLoopView, ComposeOverlayController).

import Foundation

@MainActor
protocol AgentSessionObserver: AnyObject {
    func session(_ session: AgentSession, didTransitionTo phase: AgentPhase)
    func session(_ session: AgentSession, didRequestApproval context: ApprovalContext)
    func session(_ session: AgentSession, didProduce artifact: AgentArtifact)
    func session(_ session: AgentSession, didComplete result: AgentResult)
}

// Default no-op implementations so observers only handle the events they care about.
extension AgentSessionObserver {
    func session(_ session: AgentSession, didTransitionTo phase: AgentPhase) {}
    func session(_ session: AgentSession, didRequestApproval context: ApprovalContext) {}
    func session(_ session: AgentSession, didProduce artifact: AgentArtifact) {}
    func session(_ session: AgentSession, didComplete result: AgentResult) {}
}
