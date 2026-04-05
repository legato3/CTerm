// ApprovalContext.swift
// CTerm
//
// Unified approval model. Replaces ApprovalRequirement (AgentSessionState) plus
// scattered per-call RiskAssessment usage. One context per pending approval —
// either whole-plan (stepID == nil) or step-level.

import Foundation

/// Coarse per-session approval flag. Paired with per-step ApprovalContext for
/// fine-grained decisions. Replaces the enum previously in AgentSessionState.
enum ApprovalRequirement: String, Sendable {
    case none       // auto-approved (safe read-only ops)
    case planLevel  // approve the whole plan at once
}

enum ApprovalScope: String, Sendable, Codable {
    case once             // approve just this action
    case thisTask         // trust for remainder of this session
    case thisRepo         // trust for future sessions in this working dir
    case thisSession      // trust for all sessions until app quit
}

enum ApprovalAnswer: String, Sendable, Codable {
    case approved
    case denied
    case deferred         // user dismissed without deciding
}

/// Human-facing description of what a pending action will do.
struct ActionDescriptor: Sendable, Codable {
    let what: String              // e.g. "Run: git push --force origin main"
    let why: String               // e.g. "To publish the rebased history"
    let impact: String            // e.g. "Overwrites remote main branch"
    let rollback: String?         // e.g. "git reflog to find previous commit"
}

struct ApprovalContext: Sendable {
    let stepID: UUID?             // nil = whole-plan approval
    let riskScore: Int            // 0-100, from RiskScorer
    let riskTier: RiskTier        // derived from score
    let action: ActionDescriptor
    let grantKey: GrantKey?
    let suggestedScope: ApprovalScope
    var decision: ApprovalAnswer?
    var grantedScope: ApprovalScope?

    init(
        stepID: UUID?,
        riskScore: Int,
        riskTier: RiskTier,
        action: ActionDescriptor,
        grantKey: GrantKey? = nil,
        suggestedScope: ApprovalScope = .once
    ) {
        self.stepID = stepID
        self.riskScore = riskScore
        self.riskTier = riskTier
        self.action = action
        self.grantKey = grantKey
        self.suggestedScope = suggestedScope
        self.decision = nil
        self.grantedScope = nil
    }

    var isResolved: Bool { decision != nil }
}
