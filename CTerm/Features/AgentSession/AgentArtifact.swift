// AgentArtifact.swift
// CTerm
//
// Single observation/output produced during session execution. Artifacts
// accumulate on an AgentSession and feed the result summary, memory writes,
// and suggestion ranking.

import Foundation

struct AgentArtifact: Identifiable, Sendable, Codable {
    let id: UUID
    let kind: Kind
    let value: String
    let createdAt: Date

    enum Kind: String, Sendable, Codable {
        case fileChanged
        case commandOutput
        case memoryWritten
        case peerMessage
        case diffGenerated
        case browserFinding
    }

    init(kind: Kind, value: String) {
        self.id = UUID()
        self.kind = kind
        self.value = value
        self.createdAt = Date()
    }
}
