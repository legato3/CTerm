// DelegationContract.swift
// CTerm
//
// Models for multi-agent task delegation: contracts, results, and aggregation.
// A delegation contract represents a sub-task assigned by one agent to another,
// with expected output format, timeout, and retry policy.

import Foundation

// MARK: - DelegationStatus

enum DelegationStatus: String, Sendable, Codable {
    case pending       // assigned but not yet accepted
    case accepted      // target peer acknowledged
    case running       // target peer is working
    case completed     // result received
    case failed        // peer returned error or malformed result
    case timedOut      // deadline exceeded
    case peerLost      // target peer disappeared (TTL expired)
    case cancelled     // owner cancelled

    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .timedOut, .peerLost, .cancelled: return true
        default: return false
        }
    }

    var icon: String {
        switch self {
        case .pending:   return "clock"
        case .accepted:  return "hand.thumbsup"
        case .running:   return "play.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed:    return "xmark.circle.fill"
        case .timedOut:  return "clock.badge.exclamationmark"
        case .peerLost:  return "person.slash"
        case .cancelled: return "stop.circle"
        }
    }
}

// MARK: - ExpectedOutputFormat

enum ExpectedOutputFormat: String, Sendable, Codable {
    case freeText       // any text response
    case json           // must parse as valid JSON
    case diff           // unified diff format
    case testResults    // pass/fail summary
    case reviewNotes    // structured review feedback
}

// MARK: - DelegationContract

struct DelegationContract: Identifiable, Sendable, Codable {
    let id: UUID
    let ownerPeerID: UUID
    let targetPeerName: String
    var targetPeerID: UUID?
    let prompt: String
    let expectedFormat: ExpectedOutputFormat
    let timeoutSeconds: TimeInterval
    let maxRetries: Int
    let groupID: UUID?          // for aggregation — contracts in the same group are combined
    let createdAt: Date

    var status: DelegationStatus
    var result: DelegationResult?
    var acceptedAt: Date?
    var startedAt: Date?
    var completedAt: Date?
    var retryCount: Int
    var lastError: String?
    /// Id of the unified AgentSession tracking this contract's lifecycle.
    var sessionID: UUID?

    init(
        ownerPeerID: UUID,
        targetPeerName: String,
        prompt: String,
        expectedFormat: ExpectedOutputFormat = .freeText,
        timeoutSeconds: TimeInterval = 300,
        maxRetries: Int = 1,
        groupID: UUID? = nil
    ) {
        self.id = UUID()
        self.ownerPeerID = ownerPeerID
        self.targetPeerName = targetPeerName
        self.prompt = prompt
        self.expectedFormat = expectedFormat
        self.timeoutSeconds = timeoutSeconds
        self.maxRetries = maxRetries
        self.groupID = groupID
        self.createdAt = Date()
        self.status = .pending
        self.retryCount = 0
    }

    var isOverdue: Bool {
        guard !status.isTerminal else { return false }
        return Date().timeIntervalSince(createdAt) > timeoutSeconds
    }

    var elapsedSeconds: TimeInterval {
        Date().timeIntervalSince(startedAt ?? createdAt)
    }
}

// MARK: - DelegationResult

struct DelegationResult: Sendable, Codable {
    let content: String
    let format: ExpectedOutputFormat
    let peerName: String
    let receivedAt: Date
    let isValid: Bool           // true if content matches expected format

    init(content: String, format: ExpectedOutputFormat, peerName: String) {
        self.content = content
        self.format = format
        self.peerName = peerName
        self.receivedAt = Date()
        self.isValid = Self.validate(content: content, format: format)
    }

    private static func validate(content: String, format: ExpectedOutputFormat) -> Bool {
        switch format {
        case .freeText:
            return !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .json:
            guard let data = content.data(using: .utf8) else { return false }
            return (try? JSONSerialization.jsonObject(with: data)) != nil
        case .diff:
            return content.contains("---") || content.contains("+++") || content.contains("@@")
        case .testResults:
            let lower = content.lowercased()
            return lower.contains("pass") || lower.contains("fail") || lower.contains("test")
        case .reviewNotes:
            return content.count > 10
        }
    }
}

// MARK: - AggregatedResult

struct AggregatedResult: Identifiable, Sendable {
    let id: UUID  // groupID
    let contracts: [DelegationContract]
    let completedResults: [DelegationResult]
    let failedContracts: [DelegationContract]
    let isComplete: Bool

    var summary: String {
        let total = contracts.count
        let done = completedResults.count
        let failed = failedContracts.count
        if isComplete && failed == 0 {
            return "All \(total) sub-tasks completed successfully."
        } else if isComplete {
            return "\(done)/\(total) completed, \(failed) failed."
        }
        return "\(done)/\(total) in progress..."
    }

    /// Combine all results into a single text block for the delegating agent.
    var combinedOutput: String {
        completedResults.enumerated().map { i, r in
            "--- Result \(i + 1) from \(r.peerName) ---\n\(r.content)"
        }.joined(separator: "\n\n")
    }
}
