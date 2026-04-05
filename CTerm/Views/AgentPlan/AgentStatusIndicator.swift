// AgentStatusIndicator.swift
// CTerm
//
// Small pulsing dot overlay for tabs that have an active agent session.
// 🟢 planning/executing, 🟡 awaiting approval, ✅ completed, 🔴 failed

import SwiftUI

struct AgentStatusIndicator: View {
    let agentStatus: OllamaAgentStatus?
    let planStatus: AgentPlanStatus?

    var body: some View {
        if let status = effectiveStatus {
            Circle()
                .fill(status.color)
                .frame(width: 6, height: 6)
                .shadow(color: status.color.opacity(0.5), radius: 2)
                .symbolEffect(.pulse, isActive: status.isActive)
                .help(status.tooltip)
        }
    }

    private var effectiveStatus: IndicatorStatus? {
        // Plan status takes precedence if present
        if let planStatus {
            switch planStatus {
            case .planning:  return .planning
            case .ready:     return .ready
            case .executing: return .executing
            case .paused:    return .paused
            case .completed: return .completed
            case .failed:    return .failed
            }
        }

        // Fall back to agent session status
        guard let agentStatus else { return nil }
        switch agentStatus {
        case .planning:          return .planning
        case .awaitingApproval:  return .ready
        case .runningCommand:    return .executing
        case .completed:         return .completed
        case .failed:            return .failed
        case .stopped:           return nil
        }
    }
}

private enum IndicatorStatus {
    case planning
    case ready
    case executing
    case paused
    case completed
    case failed

    var color: Color {
        switch self {
        case .planning:  return .blue
        case .ready:     return .orange
        case .executing: return .green
        case .paused:    return .yellow
        case .completed: return .green
        case .failed:    return .red
        }
    }

    var isActive: Bool {
        switch self {
        case .planning, .executing: return true
        default: return false
        }
    }

    var tooltip: String {
        switch self {
        case .planning:  return "Agent is planning…"
        case .ready:     return "Awaiting approval"
        case .executing: return "Agent is executing"
        case .paused:    return "Agent paused"
        case .completed: return "Agent completed"
        case .failed:    return "Agent failed"
        }
    }
}
