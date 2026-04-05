// DelegationDashboardState.swift
// CTerm
//
// Observable state for the delegation dashboard UI.
// Refreshed by DelegationCoordinator whenever contracts change.

import Foundation

@MainActor @Observable
final class DelegationDashboardState {
    static let shared = DelegationDashboardState()

    private(set) var contracts: [DelegationContract] = []
    private(set) var peerAssignments: [String: [DelegationContract]] = [:]

    private init() {}

    func refresh(_ snapshot: [DelegationContract]) {
        contracts = snapshot.sorted { $0.createdAt > $1.createdAt }
        // Group by target peer name
        var assignments: [String: [DelegationContract]] = [:]
        for c in contracts where !c.status.isTerminal {
            assignments[c.targetPeerName, default: []].append(c)
        }
        peerAssignments = assignments
    }

    var activeCount: Int {
        contracts.filter { !$0.status.isTerminal }.count
    }

    var completedCount: Int {
        contracts.filter { $0.status == .completed }.count
    }

    var failedCount: Int {
        contracts.filter { $0.status == .failed || $0.status == .timedOut || $0.status == .peerLost }.count
    }

    /// Unique group IDs with at least one active contract.
    var activeGroupIDs: [UUID] {
        let ids = Set(contracts.compactMap(\.groupID))
        return Array(ids)
    }
}
