// AgentPermissions.swift
// CTerm
//
// Two-mode agent permissions: "Ask me" (default) or "Trust this session."
// No profiles, no per-category matrix, no batching. Simple and controllable.

import Foundation
import Observation

// MARK: - Agent Trust Mode

enum AgentTrustMode: String, Codable, Sendable {
    /// Default: agent asks before any non-read-only action.
    case askMe = "askMe"
    /// User trusts the agent for this session. Only critical-risk actions ask.
    case trustSession = "trustSession"

    var displayName: String {
        switch self {
        case .askMe:        return "Ask me"
        case .trustSession: return "Trust this session"
        }
    }

    var description: String {
        switch self {
        case .askMe:        return "Agent asks before running commands, writing files, or making changes."
        case .trustSession: return "Agent runs freely. Only destructive or irreversible actions ask."
        }
    }

    var icon: String {
        switch self {
        case .askMe:        return "lock.shield"
        case .trustSession: return "checkmark.shield"
        }
    }
}

// MARK: - Action Category (kept for RiskScorer compatibility)

enum AgentActionCategory: String, Codable, CaseIterable, Sendable {
    case readFiles      = "readFiles"
    case writeFiles     = "writeFiles"
    case runCommands    = "runCommands"
    case networkAccess  = "networkAccess"
    case gitOperations  = "gitOperations"
    case deleteFiles    = "deleteFiles"
    case browserAutomation = "browserAutomation"
    case interactivePrompt = "interactivePrompt"

    var displayName: String {
        switch self {
        case .readFiles:           return "Read files"
        case .writeFiles:          return "Write / edit files"
        case .runCommands:         return "Run shell commands"
        case .networkAccess:       return "Network access"
        case .gitOperations:       return "Git operations"
        case .deleteFiles:         return "Delete files"
        case .browserAutomation:   return "Browser automation"
        case .interactivePrompt:   return "Respond to interactive prompt"
        }
    }

    var icon: String {
        switch self {
        case .readFiles:           return "doc.text"
        case .writeFiles:          return "pencil"
        case .runCommands:         return "terminal"
        case .networkAccess:       return "network"
        case .gitOperations:       return "arrow.triangle.branch"
        case .deleteFiles:         return "trash"
        case .browserAutomation:   return "globe"
        case .interactivePrompt:   return "keyboard"
        }
    }
}

// MARK: - Store

@Observable
@MainActor
final class AgentPermissionsStore {
    static let shared = AgentPermissionsStore()

    /// Current trust mode for this session.
    var trustMode: AgentTrustMode = .askMe {
        didSet {
            UserDefaults.standard.set(trustMode.rawValue, forKey: "cterm.agentTrustMode")
        }
    }

    private init() {
        if let raw = UserDefaults.standard.string(forKey: "cterm.agentTrustMode"),
           let mode = AgentTrustMode(rawValue: raw) {
            self.trustMode = mode
        }
    }

    /// Decide whether an action should proceed based on its risk assessment.
    func decide(for assessment: RiskAssessment) -> ApprovalDecision {
        // Read-only is always auto-approved regardless of mode
        if assessment.category == .readFiles {
            return .autoApprove
        }

        switch trustMode {
        case .askMe:
            // Only auto-approve low-risk (score < 20)
            if assessment.score < 20 {
                return .autoApprove
            }
            return .requireApproval

        case .trustSession:
            // Auto-approve everything except critical-risk (score >= 80)
            if assessment.score >= 80 {
                return .requireApproval
            }
            return .autoApprove
        }
    }

    /// Quick check: should this category auto-allow?
    func shouldAutoAllow(_ category: AgentActionCategory) -> Bool {
        if category == .readFiles { return true }
        return trustMode == .trustSession
    }

    /// Is this category blocked entirely?
    func isBlocked(_ category: AgentActionCategory) -> Bool {
        false // nothing is hard-blocked in the two-mode system
    }

    /// Risk threshold for auto-approval.
    var autoApproveThreshold: Int {
        switch trustMode {
        case .askMe:        return 20
        case .trustSession: return 80
        }
    }
}

// MARK: - Approval Decision

enum ApprovalDecision: Sendable {
    case autoApprove
    case requireApproval
    case blocked(reason: String)
}
