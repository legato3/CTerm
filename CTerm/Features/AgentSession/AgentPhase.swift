// AgentPhase.swift
// CTerm
//
// Unified phase machine for all agent sessions. Replaces the five separate
// phase enums that previously lived in AgentSessionState, OllamaAgentSession,
// AgentPlanStatus, TaskLifecycle, and DelegationContract.

import Foundation

enum AgentPhase: String, Sendable, Codable {
    case idle
    case thinking          // classifying + planning
    case awaitingApproval
    case running           // executing + observing + delegating + browsing
    case summarizing
    case completed
    case failed
    case cancelled

    /// Alias matching the legacy AgentSessionState.phase.label API.
    var label: String { userLabel }

    /// User-visible label collapsed to 3 buckets: Thinking / Running / Done.
    var userLabel: String {
        switch self {
        case .idle:             return "Idle"
        case .thinking:         return "Thinking"
        case .awaitingApproval: return "Awaiting Approval"
        case .running:          return "Running"
        case .summarizing:      return "Running"
        case .completed:        return "Done"
        case .failed:           return "Failed"
        case .cancelled:        return "Cancelled"
        }
    }

    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled: return true
        default: return false
        }
    }

    var isActive: Bool {
        switch self {
        case .thinking, .running, .summarizing: return true
        default: return false
        }
    }
}
