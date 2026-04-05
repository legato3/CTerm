// AgentSessionState.swift
// CTerm
//
// State machine for the agent loop pipeline.
// Internal phases are granular for logic; the user-visible state is collapsed
// to three states: Thinking, Running, Done.

import Foundation
import Observation
import OSLog

private let logger = Logger(subsystem: "com.legato3.cterm", category: "AgentSessionState")

// MARK: - Phase

enum AgentPhase: String, Sendable {
    case idle
    case classifying
    case planning
    case awaitingApproval
    case executing
    case observing
    case summarizing
    case completed
    case failed

    /// User-visible label — collapsed to 3 states.
    var label: String {
        switch self {
        case .idle:             return "Idle"
        case .classifying,
             .planning:         return "Thinking"
        case .awaitingApproval: return "Awaiting Approval"
        case .executing,
             .observing,
             .summarizing:      return "Running"
        case .completed:        return "Done"
        case .failed:           return "Failed"
        }
    }

    var isTerminal: Bool {
        self == .completed || self == .failed
    }

    var isActive: Bool {
        switch self {
        case .classifying, .planning, .executing, .observing, .summarizing:
            return true
        default:
            return false
        }
    }
}

// MARK: - Approval Requirement

enum ApprovalRequirement: String, Sendable {
    case none       // auto-approved (safe read-only ops)
    case planLevel  // approve the whole plan at once
}

// MARK: - Artifact

struct AgentArtifact: Identifiable, Sendable {
    let id: UUID
    let kind: Kind
    let value: String
    let createdAt: Date

    enum Kind: String, Sendable {
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

// MARK: - Session State

@Observable
@MainActor
final class AgentSessionState: Identifiable {
    let id: UUID
    let userIntent: String
    let tabID: UUID?
    let startedAt: Date

    /// Current phase in the pipeline.
    private(set) var phase: AgentPhase = .idle {
        didSet {
            guard oldValue != phase else { return }
            updatedAt = Date()
            logger.info("AgentSession [\(self.id.uuidString.prefix(8))]: \(oldValue.rawValue) → \(self.phase.rawValue)")
            SessionAuditLogger.log(
                type: .agentPhaseChanged,
                detail: "Agent phase: \(oldValue.rawValue) → \(phase.rawValue)"
            )
        }
    }

    /// Classified intent (set after classifying phase).
    var classifiedIntent: IntentCategory?

    /// The plan steps (set after planning phase).
    var planSteps: [AgentPlanStep] = []

    /// Index of the currently executing step.
    var currentStepIndex: Int?

    /// What level of approval is required.
    var approvalRequirement: ApprovalRequirement = .planLevel

    /// Accumulated artifacts from execution.
    var artifacts: [AgentArtifact] = []

    /// Completion summary (set after summarizing phase).
    var summary: String?

    /// Suggested next actions (set after summarizing phase).
    var nextActions: [String] = []

    /// Error message if failed.
    var errorMessage: String?

    var updatedAt: Date

    init(userIntent: String, tabID: UUID? = nil) {
        self.id = UUID()
        self.userIntent = userIntent
        self.tabID = tabID
        self.startedAt = Date()
        self.updatedAt = Date()
    }

    // MARK: - Phase Transitions

    func transitionTo(_ newPhase: AgentPhase) {
        phase = newPhase
    }

    func fail(message: String) {
        errorMessage = message
        phase = .failed
    }

    func addArtifact(_ artifact: AgentArtifact) {
        artifacts.append(artifact)
    }

    // MARK: - Derived

    var displayIntent: String {
        let trimmed = userIntent.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = trimmed.range(of: "\n\n<cterm_agent_context>") {
            return String(trimmed[..<range.lowerBound])
        }
        return trimmed
    }

    var progress: Double {
        guard !planSteps.isEmpty else { return 0 }
        let done = planSteps.filter { $0.status.isTerminal }.count
        return Double(done) / Double(planSteps.count)
    }

    var elapsedSeconds: TimeInterval {
        Date().timeIntervalSince(startedAt)
    }

    /// Compact status string for the always-visible progress strip.
    var progressLabel: String {
        guard !planSteps.isEmpty else { return phase.label }
        let done = planSteps.filter { $0.status.isTerminal }.count
        let running = planSteps.first(where: { $0.status == .running })
        if let running {
            return "Step \(done + 1)/\(planSteps.count): \(running.title.prefix(40))"
        }
        return "\(done)/\(planSteps.count) steps"
    }
}
