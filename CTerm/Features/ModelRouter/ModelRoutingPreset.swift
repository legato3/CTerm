// ModelRoutingPreset.swift
// CTerm
//
// A routing preset assigns each StepRole to a SimpleBackend (ollama or
// claudeSubscription). Peer backends are per-delegation and cannot be
// routed via a preset.

import Foundation

struct ModelRoutingPreset: Codable, Hashable, Identifiable, Sendable {
    let id: String             // stable: "localFirst", "claudeFirst", "allOllama", "allClaude", "custom"
    let name: String           // display
    let description: String
    let assignments: [StepRole: SimpleBackend]

    enum SimpleBackend: String, Codable, Hashable, Sendable {
        case ollama
        case claudeSubscription

        var displayName: String {
            switch self {
            case .ollama:             return "Ollama"
            case .claudeSubscription: return "Claude"
            }
        }

        var agentBackend: AgentBackend {
            switch self {
            case .ollama:             return .ollama
            case .claudeSubscription: return .claudeSubscription
            }
        }
    }
}

// MARK: - Built-in presets

extension ModelRoutingPreset {

    static let localFirst = ModelRoutingPreset(
        id: "localFirst",
        name: "Local first",
        description: "Ollama for fast work, Claude for code generation",
        assignments: [
            .classifying: .ollama,
            .planning: .ollama,
            .coding: .claudeSubscription,
            .browsing: .ollama,
            .summarizing: .ollama,
            .explaining: .claudeSubscription,
        ]
    )

    static let claudeFirst = ModelRoutingPreset(
        id: "claudeFirst",
        name: "Claude first",
        description: "Claude everywhere except cheap summarization",
        assignments: [
            .classifying: .claudeSubscription,
            .planning: .claudeSubscription,
            .coding: .claudeSubscription,
            .browsing: .claudeSubscription,
            .summarizing: .ollama,
            .explaining: .claudeSubscription,
        ]
    )

    static let allOllama = ModelRoutingPreset(
        id: "allOllama",
        name: "All Ollama",
        description: "Local-only, no external LLM calls",
        assignments: Dictionary(uniqueKeysWithValues: StepRole.allCases.map { ($0, .ollama) })
    )

    static let allClaude = ModelRoutingPreset(
        id: "allClaude",
        name: "All Claude",
        description: "Claude for every step",
        assignments: Dictionary(uniqueKeysWithValues: StepRole.allCases.map { ($0, .claudeSubscription) })
    )

    static let builtIn: [ModelRoutingPreset] = [.localFirst, .claudeFirst, .allOllama, .allClaude]
}
