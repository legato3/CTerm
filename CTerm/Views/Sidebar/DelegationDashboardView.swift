// DelegationDashboardView.swift
// CTerm
//
// Minimal sidebar view showing active peer roles, current delegation
// assignments, and peer health status.

import SwiftUI

struct DelegationDashboardView: View {
    @State private var agentState = IPCAgentState.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            if !agentState.isRunning {
                offlineMessage
            } else if agentState.delegationContracts.isEmpty {
                emptyMessage
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        summaryBar
                        peerRolesSection
                        activeDelegationsSection
                        if failedCount > 0 {
                            failedSection
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Delegations")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
            Spacer()
            if agentState.activeDelegationCount > 0 {
                Text("\(agentState.activeDelegationCount) active")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Summary

    private var activeCount: Int {
        agentState.delegationContracts.filter { !$0.status.isTerminal }.count
    }
    private var completedCount: Int {
        agentState.delegationContracts.filter { $0.status == .completed }.count
    }
    private var failedCount: Int {
        agentState.delegationContracts.filter { $0.status == .failed || $0.status == .timedOut || $0.status == .peerLost }.count
    }
    private var peerAssignments: [String: [DelegationContract]] {
        var assignments: [String: [DelegationContract]] = [:]
        for c in agentState.delegationContracts where !c.status.isTerminal {
            assignments[c.targetPeerName, default: []].append(c)
        }
        return assignments
    }

    private var summaryBar: some View {
        HStack(spacing: 12) {
            summaryPill(count: activeCount, label: "Active", color: .blue)
            summaryPill(count: completedCount, label: "Done", color: .green)
            summaryPill(count: failedCount, label: "Failed", color: .red)
        }
    }

    private func summaryPill(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(count)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Peer Roles

    private var peerRolesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Peer Assignments")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)

            let externalPeers = agentState.peers.filter { $0.name != "cterm-app" }
            if externalPeers.isEmpty {
                Text("No peers connected")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(externalPeers, id: \.id) { peer in
                    PeerRoleRow(
                        peer: peer,
                        assignments: peerAssignments[peer.name] ?? []
                    )
                }
            }
        }
    }

    // MARK: - Active Delegations

    private var activeDelegationsSection: some View {
        let active = agentState.delegationContracts.filter { !$0.status.isTerminal }
        return VStack(alignment: .leading, spacing: 6) {
            if !active.isEmpty {
                Text("Active Tasks")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                ForEach(active, id: \.id) { contract in
                    DelegationRow(contract: contract)
                }
            }
        }
    }

    // MARK: - Failed

    private var failedSection: some View {
        let failed = agentState.delegationContracts.filter {
            $0.status == .failed || $0.status == .timedOut || $0.status == .peerLost
        }
        return VStack(alignment: .leading, spacing: 6) {
            Text("Failed")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.red.opacity(0.7))
            ForEach(failed, id: \.id) { contract in
                DelegationRow(contract: contract)
            }
        }
    }

    // MARK: - Offline / Empty

    private var offlineMessage: some View {
        VStack(spacing: 6) {
            Image(systemName: "network.slash")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("MCP server offline")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var emptyMessage: some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("No delegations yet")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text("Use delegate_task from an orchestrator agent")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 16)
    }
}

// MARK: - PeerRoleRow

private struct PeerRoleRow: View {
    let peer: Peer
    let assignments: [DelegationContract]

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(peer.name)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                    if !peer.role.isEmpty {
                        Text("(\(peer.role))")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
                if assignments.isEmpty {
                    Text("idle")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                } else {
                    Text("\(assignments.count) task\(assignments.count == 1 ? "" : "s") assigned")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(AgentStatus.infer(from: peer).label)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(.ultraThinMaterial))
    }

    private var statusColor: Color {
        switch AgentStatus.infer(from: peer) {
        case .active:       return .green
        case .idle:         return .yellow
        case .disconnected: return .gray
        }
    }
}

// MARK: - DelegationRow

private struct DelegationRow: View {
    let contract: DelegationContract

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: contract.status.icon)
                .font(.system(size: 10))
                .foregroundStyle(iconColor)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("→ \(contract.targetPeerName)")
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    Spacer()
                    Text(elapsedText)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                Text(String(contract.prompt.prefix(80)))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let error = contract.lastError {
                    Text(error)
                        .font(.system(size: 8))
                        .foregroundStyle(.red.opacity(0.8))
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(.ultraThinMaterial))
    }

    private var iconColor: Color {
        switch contract.status {
        case .completed: return .green
        case .running, .accepted: return .blue
        case .pending: return .orange
        case .failed, .timedOut, .peerLost: return .red
        case .cancelled: return .gray
        }
    }

    private var elapsedText: String {
        let s = Int(contract.elapsedSeconds)
        if s < 60 { return "\(s)s" }
        return "\(s / 60)m"
    }
}
