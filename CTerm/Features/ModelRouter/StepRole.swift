// StepRole.swift
// CTerm
//
// Roles a plan step can play. The ModelRouter maps each role to an
// AgentBackend based on the active routing preset. Plan steps carry a
// precomputed `backendHint` derived from their role + the active preset.

import Foundation

enum StepRole: String, Codable, Hashable, CaseIterable, Sendable {
    case classifying    // intent classification, fast cheap
    case planning       // multi-step plan generation
    case coding         // code generation/editing (highest quality)
    case browsing       // browser research steps
    case summarizing    // result summarization, fast
    case explaining     // file/code explanation

    var displayName: String {
        switch self {
        case .classifying: return "Classifying"
        case .planning:    return "Planning"
        case .coding:      return "Coding"
        case .browsing:    return "Browsing"
        case .summarizing: return "Summarizing"
        case .explaining:  return "Explaining"
        }
    }
}
