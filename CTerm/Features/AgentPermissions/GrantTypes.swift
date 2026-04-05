// GrantTypes.swift
// CTerm
//
// Types used by AgentGrantStore and ApprovalGate to match and persist
// per-action grants. Grants are keyed by (category, riskTier, commandPrefix)
// so that approving `git status` does not silently authorize `git push --force`.

import Foundation
import CryptoKit

/// A hashable identifier for the kind of action being approved.
/// Matched across calls to decide whether a previously-granted scope covers
/// this action.
struct GrantKey: Hashable, Codable, Sendable {
    let category: AgentActionCategory
    let riskTier: RiskTier
    let commandPrefix: String   // first token of the command, lowercased

    init(category: AgentActionCategory, riskTier: RiskTier, commandPrefix: String) {
        self.category = category
        self.riskTier = riskTier
        self.commandPrefix = commandPrefix.lowercased()
    }

    /// Build a grant key from a raw command + risk assessment.
    static func from(command: String, assessment: RiskAssessment) -> GrantKey {
        let prefix = command
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ", maxSplits: 1)
            .first
            .map(String.init) ?? ""
        return GrantKey(
            category: assessment.category,
            riskTier: assessment.tier,
            commandPrefix: prefix
        )
    }

    /// Build a grant key for a browser tool call.
    static func browser(tier: RiskTier, tool: String) -> GrantKey {
        GrantKey(
            category: .browserAutomation,
            riskTier: tier,
            commandPrefix: tool.lowercased()
        )
    }
}

/// Context passed to the grant lookup — which session is asking, and which
/// repo (by stable hash) are we inside.
struct GrantContext: Sendable {
    let sessionID: UUID?
    let repoKey: String?

    init(sessionID: UUID?, pwd: String?) {
        self.sessionID = sessionID
        self.repoKey = pwd.flatMap(Self.key(forPwd:))
    }

    /// Stable 16-char SHA-256 prefix of the working directory path.
    /// Used as a filename — no PII, stable across sessions.
    static func key(forPwd pwd: String) -> String {
        let digest = SHA256.hash(data: Data(pwd.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(16))
    }
}

/// Payload for a single persisted repo-scope grant.
struct RepoGrantEntry: Codable, Equatable, Sendable {
    let category: AgentActionCategory
    let riskTier: RiskTier
    let commandPrefix: String
    let grantedAt: Date

    var key: GrantKey {
        GrantKey(category: category, riskTier: riskTier, commandPrefix: commandPrefix)
    }

    init(key: GrantKey, grantedAt: Date = Date()) {
        self.category = key.category
        self.riskTier = key.riskTier
        self.commandPrefix = key.commandPrefix
        self.grantedAt = grantedAt
    }
}

/// File-format wrapper for a single repo's grants.
struct RepoGrantsFile: Codable, Sendable {
    static let currentVersion = 1
    let version: Int
    let repoKey: String
    let repoPath: String
    var grants: [RepoGrantEntry]

    init(repoKey: String, repoPath: String, grants: [RepoGrantEntry] = []) {
        self.version = Self.currentVersion
        self.repoKey = repoKey
        self.repoPath = repoPath
        self.grants = grants
    }
}

// Codable conformance for RiskTier (it's already Sendable+Comparable).
extension RiskTier: Codable {}
