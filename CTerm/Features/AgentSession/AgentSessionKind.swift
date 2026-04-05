// AgentSessionKind.swift
// CTerm
//
// Classifies where an AgentSession came from. Every spawner (compose overlay,
// MCP queue_task, MCP delegate_task, full multi-step pipeline) maps to one kind.

import Foundation

enum AgentSessionKind: String, Sendable, Codable {
    /// Single-loop inline agent driven from the compose bar.
    /// Replaces OllamaAgentSession.
    case inline

    /// Classify → plan → approve → execute → summarize pipeline.
    /// Replaces AgentSessionState.
    case multiStep

    /// Wrapped queued task from TaskQueueStore.
    case queued

    /// Local projection of a remote peer contract from DelegationCoordinator.
    case delegated
}

/// Which backend drives planning and execution for this session.
enum AgentBackend: Sendable, Codable, Equatable, Hashable {
    case ollama
    case claudeSubscription
    case peer(name: String)

    var displayName: String {
        switch self {
        case .ollama:             return "Ollama"
        case .claudeSubscription: return "Claude"
        case .peer(let name):     return name
        }
    }

    /// Down-cast to the legacy planning backend enum (nil for peer backends).
    var planningBackend: AgentPlanningBackend? {
        switch self {
        case .ollama:             return .ollama
        case .claudeSubscription: return .claudeSubscription
        case .peer:               return nil
        }
    }
}
