// InlineAgentStep.swift
// CTerm
//
// Step entry used by inline-kind AgentSessions (compose-bar loop).
// Replaces OllamaAgentStep; the shape is unchanged so existing UI
// bindings continue to work.

import Foundation

enum InlineAgentStepKind: String, Sendable, Codable {
    case goal
    case plan
    case command
    case observation
    case summary
    case error

    var title: String {
        switch self {
        case .goal: return "Goal"
        case .plan: return "Plan"
        case .command: return "Command"
        case .observation: return "Observation"
        case .summary: return "Summary"
        case .error: return "Error"
        }
    }
}

struct InlineAgentStep: Identifiable, Sendable, Codable, Equatable {
    let id: UUID
    let kind: InlineAgentStepKind
    let text: String
    let command: String?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        kind: InlineAgentStepKind,
        text: String,
        command: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.command = command
        self.createdAt = createdAt
    }
}

/// Compat typealiases used while OllamaAgentSession callers migrate.
typealias OllamaAgentStep = InlineAgentStep
typealias OllamaAgentStepKind = InlineAgentStepKind
