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

/// When present, the approval sheet renders a secure text field (password
/// entry) in place of the standard descriptor rows. The entered value is
/// passed directly to the approval resume callback and is never logged,
/// persisted, or stashed on the session.
struct ApprovalSecureInputRequest: Sendable {
    let fieldLabel: String        // e.g. "Password"
    let placeholder: String       // e.g. "Enter password for sudo"
    let matchedLine: String       // e.g. "[sudo] password for chris:"
}

struct ApprovalContext: Sendable {
    let stepID: UUID?             // nil = whole-plan approval
    let riskScore: Int            // 0-100, from RiskScorer
    let riskTier: RiskTier        // derived from score
    let action: ActionDescriptor
    let grantKey: GrantKey?
    let suggestedScope: ApprovalScope
    /// Optional secure-input override. When non-nil the sheet renders a
    /// SecureField and the entered text flows back through the resume
    /// callback. Defaults to nil so existing approval paths are unchanged.
    let secureInputRequest: ApprovalSecureInputRequest?
    var decision: ApprovalAnswer?
    var grantedScope: ApprovalScope?

    init(
        stepID: UUID?,
        riskScore: Int,
        riskTier: RiskTier,
        action: ActionDescriptor,
        grantKey: GrantKey? = nil,
        suggestedScope: ApprovalScope = .once,
        secureInputRequest: ApprovalSecureInputRequest? = nil
    ) {
        self.stepID = stepID
        self.riskScore = riskScore
        self.riskTier = riskTier
        self.action = action
        self.grantKey = grantKey
        self.suggestedScope = suggestedScope
        self.secureInputRequest = secureInputRequest
        self.decision = nil
        self.grantedScope = nil
    }

    var isResolved: Bool { decision != nil }
}
