// InlineAgentStatus.swift
// CTerm
//
// Enums extracted from the retired OllamaAgentSession struct. They still drive
// the compose-bar inline-agent UI; OllamaAgentStatus is now a projection of
// the unified AgentPhase plus approval/pending-command state.

import Foundation

enum AgentPlanningBackend: String, Sendable, Codable {
    case ollama
    case claudeSubscription
}

enum OllamaAgentStatus: String, Sendable {
    case planning
    case awaitingApproval
    case runningCommand
    case completed
    case failed
    case stopped

    var label: String {
        switch self {
        case .planning: return "Planning"
        case .awaitingApproval: return "Awaiting Approval"
        case .runningCommand: return "Running"
        case .completed: return "Done"
        case .failed: return "Failed"
        case .stopped: return "Stopped"
        }
    }

    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .stopped: return true
        default: return false
        }
    }
}
