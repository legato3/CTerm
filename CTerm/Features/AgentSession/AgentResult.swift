// AgentResult.swift
// CTerm
//
// Post-run summary for an AgentSession. Feeds ActiveAISuggestionEngine,
// handoff memory, and the user-facing completion panel.

import Foundation

struct NextAction: Sendable, Codable, Identifiable {
    let id: UUID
    let label: String              // short user-visible prompt
    let prompt: String             // full intent to pass into a follow-up session
    let confidence: Double         // 0–1

    init(label: String, prompt: String, confidence: Double = 0.7) {
        self.id = UUID()
        self.label = label
        self.prompt = prompt
        self.confidence = confidence
    }
}

struct AgentResult: Sendable, Codable {
    let summary: String
    let filesChanged: [String]
    let nextActions: [NextAction]
    let durationMs: Int
    let handoffMemoryKey: String?  // key into AgentMemoryStore if handoff was written
    let exitStatus: ExitStatus

    enum ExitStatus: String, Sendable, Codable {
        case succeeded
        case failed
        case cancelled
        case partial   // some steps succeeded, some did not
    }
}
