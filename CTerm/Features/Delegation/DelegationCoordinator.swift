// DelegationCoordinator.swift
// CTerm
//
// Actor that manages the lifecycle of delegation contracts: creation,
// peer health monitoring, timeout enforcement, retry, and result aggregation.
// Bridges between the MCP tool handlers and the IPCStore messaging layer.

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.legato3.cterm", category: "Delegation")

// MARK: - DelegationCoordinator

actor DelegationCoordinator {
    static let shared = DelegationCoordinator()

    private var contracts: [UUID: DelegationContract] = [:]
    private var monitorTask: Task<Void, Never>?
    private static let tickInterval: UInt64 = 3_000_000_000 // 3s

    private init() {}

    /// Sync the AgentSession phase to match the contract status.
    private func syncSessionPhase(for contract: DelegationContract) async {
        guard let sid = contract.sessionID else { return }
        let status = contract.status
        await MainActor.run {
            guard let session = AgentSessionRegistry.shared.session(id: sid) else { return }
            switch status {
            case .pending, .accepted: session.transition(to: .running)
            case .running:            session.transition(to: .running)
            case .completed:          session.transition(to: .completed)
            case .failed:             session.transition(to: .failed)
            case .timedOut:           session.transition(to: .failed)
            case .peerLost:           session.transition(to: .failed)
            case .cancelled:          session.transition(to: .cancelled)
            }
        }
    }

    // MARK: - Contract Lifecycle

    /// Create a new delegation contract. Sends the task prompt to the target peer
    /// via IPCStore messaging with topic "delegation".
    func createContract(
        ownerPeerID: UUID,
        targetPeerName: String,
        prompt: String,
        expectedFormat: ExpectedOutputFormat,
        timeoutSeconds: TimeInterval,
        maxRetries: Int,
        groupID: UUID?
    ) async -> DelegationContract {
        var contract = DelegationContract(
            ownerPeerID: ownerPeerID,
            targetPeerName: targetPeerName,
            prompt: prompt,
            expectedFormat: expectedFormat,
            timeoutSeconds: timeoutSeconds,
            maxRetries: maxRetries,
            groupID: groupID
        )

        // Resolve target peer
        let store = await CTermMCPServer.shared.store
        if let peer = await store.peer(named: targetPeerName) {
            contract.targetPeerID = peer.id

            // Send the delegation message
            let delegationPayload = """
            [DELEGATION task_id=\(contract.id.uuidString)]
            Expected output format: \(expectedFormat.rawValue)
            Timeout: \(Int(timeoutSeconds))s

            \(prompt)

            When done, call the report_result tool with task_id="\(contract.id.uuidString)" and your result.
            """

            do {
                _ = try await store.sendMessage(
                    from: ownerPeerID,
                    to: peer.id,
                    content: delegationPayload,
                    topic: "delegation"
                )
                logger.info("Delegation \(contract.id): sent to peer '\(targetPeerName)'")
            } catch {
                logger.warning("Delegation \(contract.id): failed to send — \(error.localizedDescription)")
                contract.lastError = error.localizedDescription
            }
        } else {
            contract.lastError = "Peer '\(targetPeerName)' not found"
            logger.warning("Delegation \(contract.id): target peer '\(targetPeerName)' not found")
        }

        // Register a local AgentSession projection so this delegation shows up
        // in the unified active-sessions list.
        let contractID = contract.id
        let peerNameCopy = targetPeerName
        let promptCopy = prompt
        let sessionID = await MainActor.run { () -> UUID in
            let session = AgentSessionRouter.shared.start(
                AgentSessionRequest(
                    intent: promptCopy,
                    kind: .delegated,
                    backend: .peer(name: peerNameCopy),
                    tabID: nil
                )
            )
            // Delegation begins immediately waiting on the peer.
            session.transition(to: .running)
            _ = contractID  // silence unused
            return session.id
        }
        contract.sessionID = sessionID

        contracts[contract.id] = contract
        ensureMonitoring()

        let snapshot = Array(contracts.values)
        await MainActor.run {
            IPCAgentState.shared.refreshDelegations(snapshot)
        }

        return contract
    }

    /// Called when a peer reports a result for a delegation.
    func reportResult(
        taskID: UUID,
        peerName: String,
        content: String
    ) async -> (accepted: Bool, error: String?) {
        guard var contract = contracts[taskID] else {
            return (false, "No delegation found with id \(taskID.uuidString)")
        }

        guard !contract.status.isTerminal else {
            return (false, "Delegation already in terminal state: \(contract.status.rawValue)")
        }

        let result = DelegationResult(
            content: content,
            format: contract.expectedFormat,
            peerName: peerName
        )

        if result.isValid {
            contract.result = result
            contract.status = .completed
            contract.completedAt = Date()
            contracts[taskID] = contract
            await syncSessionPhase(for: contract)
            logger.info("Delegation \(taskID): completed by '\(peerName)'")

            // Notify the owner peer via message
            await notifyOwner(contract: contract, message: "Delegation completed by \(peerName).")

            // Check if this completes a group
            if let groupID = contract.groupID {
                await checkGroupCompletion(groupID: groupID, ownerPeerID: contract.ownerPeerID)
            }
        } else {
            // Malformed result
            contract.lastError = "Result did not match expected format: \(contract.expectedFormat.rawValue)"
            if contract.retryCount < contract.maxRetries {
                contract.retryCount += 1
                contract.status = .pending
                contract.lastError = "Malformed result (attempt \(contract.retryCount)/\(contract.maxRetries)). Retrying."
                logger.warning("Delegation \(taskID): malformed result from '\(peerName)', retrying (\(contract.retryCount)/\(contract.maxRetries))")
                // Re-send the delegation
                await resendDelegation(&contract)
            } else {
                contract.status = .failed
                contract.completedAt = Date()
                logger.warning("Delegation \(taskID): failed — malformed result, no retries left")
                await notifyOwner(contract: contract, message: "Delegation failed: malformed result from \(peerName).")
            }
            contracts[taskID] = contract
            await syncSessionPhase(for: contract)
        }

        let reportSnapshot = Array(contracts.values)
        await MainActor.run {
            IPCAgentState.shared.refreshDelegations(reportSnapshot)
        }

        return (result.isValid, result.isValid ? nil : contract.lastError)
    }

    /// Accept a delegation (peer acknowledges it will work on it).
    func acceptDelegation(taskID: UUID) async -> Bool {
        guard var contract = contracts[taskID], contract.status == .pending else {
            return false
        }
        contract.status = .accepted
        contract.acceptedAt = Date()
        contracts[taskID] = contract
        await syncSessionPhase(for: contract)

        let acceptSnapshot = Array(contracts.values)
        await MainActor.run {
            IPCAgentState.shared.refreshDelegations(acceptSnapshot)
        }
        return true
    }

    /// Mark a delegation as running (peer started working).
    func markRunning(taskID: UUID) async {
        guard var contract = contracts[taskID],
              contract.status == .accepted || contract.status == .pending else { return }
        contract.status = .running
        contract.startedAt = Date()
        contracts[taskID] = contract
        await syncSessionPhase(for: contract)

        let runSnapshot = Array(contracts.values)
        await MainActor.run {
            IPCAgentState.shared.refreshDelegations(runSnapshot)
        }
    }

    /// Cancel a delegation.
    func cancelDelegation(taskID: UUID) async {
        guard var contract = contracts[taskID], !contract.status.isTerminal else { return }
        contract.status = .cancelled
        contract.completedAt = Date()
        contracts[taskID] = contract
        await syncSessionPhase(for: contract)

        let cancelSnapshot = Array(contracts.values)
        await MainActor.run {
            IPCAgentState.shared.refreshDelegations(cancelSnapshot)
        }
    }

    // MARK: - Queries

    func getContract(_ id: UUID) -> DelegationContract? {
        contracts[id]
    }

    func allContracts() -> [DelegationContract] {
        Array(contracts.values).sorted { $0.createdAt > $1.createdAt }
    }

    func contractsForOwner(_ ownerPeerID: UUID) -> [DelegationContract] {
        contracts.values.filter { $0.ownerPeerID == ownerPeerID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func contractsForTarget(_ targetPeerName: String) -> [DelegationContract] {
        let lower = targetPeerName.lowercased()
        return contracts.values.filter { $0.targetPeerName.lowercased() == lower }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Build an aggregated result for a delegation group.
    func aggregatedResult(groupID: UUID) -> AggregatedResult {
        let group = contracts.values.filter { $0.groupID == groupID }
        let completed = group.filter { $0.status == .completed }
        let failed = group.filter { $0.status == .failed || $0.status == .timedOut || $0.status == .peerLost }
        let allTerminal = group.allSatisfy { $0.status.isTerminal }

        return AggregatedResult(
            id: groupID,
            contracts: Array(group),
            completedResults: completed.compactMap(\.result),
            failedContracts: Array(failed),
            isComplete: allTerminal
        )
    }

    // MARK: - Monitoring

    private func ensureMonitoring() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(nanoseconds: Self.tickInterval)
            }
        }
    }

    private func tick() async {
        let store = await CTermMCPServer.shared.store
        let livePeers = await store.listPeers()
        let liveNames = Set(livePeers.map { $0.name.lowercased() })
        var changed = false

        for (id, var contract) in contracts where !contract.status.isTerminal {
            // 1. Timeout check
            if contract.isOverdue {
                if contract.retryCount < contract.maxRetries {
                    contract.retryCount += 1
                    contract.status = .pending
                    contract.lastError = "Timed out (attempt \(contract.retryCount)/\(contract.maxRetries)). Retrying."
                    logger.warning("Delegation \(id): timed out, retrying (\(contract.retryCount)/\(contract.maxRetries))")
                    await resendDelegation(&contract)
                } else {
                    contract.status = .timedOut
                    contract.completedAt = Date()
                    logger.warning("Delegation \(id): timed out, no retries left")
                    await notifyOwner(contract: contract, message: "Delegation timed out for '\(contract.targetPeerName)'.")
                }
                contracts[id] = contract
                await syncSessionPhase(for: contract)
                changed = true
                continue
            }

            // 2. Peer health check — did the target peer disappear?
            if !liveNames.contains(contract.targetPeerName.lowercased()) {
                if contract.retryCount < contract.maxRetries {
                    contract.retryCount += 1
                    contract.status = .pending
                    contract.lastError = "Peer '\(contract.targetPeerName)' disappeared (attempt \(contract.retryCount)/\(contract.maxRetries))."
                    logger.warning("Delegation \(id): peer lost, retrying")
                } else {
                    contract.status = .peerLost
                    contract.completedAt = Date()
                    logger.warning("Delegation \(id): peer '\(contract.targetPeerName)' lost, no retries left")
                    await notifyOwner(contract: contract, message: "Peer '\(contract.targetPeerName)' disappeared. Delegation failed.")
                }
                contracts[id] = contract
                await syncSessionPhase(for: contract)
                changed = true
            }
        }

        // Stop monitoring if no active contracts
        if contracts.values.allSatisfy({ $0.status.isTerminal }) {
            monitorTask?.cancel()
            monitorTask = nil
        }

        if changed {
            let snapshot = Array(contracts.values)
            await MainActor.run {
                IPCAgentState.shared.refreshDelegations(snapshot)
            }
        }
    }

    // MARK: - Helpers

    private func resendDelegation(_ contract: inout DelegationContract) async {
        let store = await CTermMCPServer.shared.store
        guard let peer = await store.peer(named: contract.targetPeerName) else { return }
        contract.targetPeerID = peer.id

        let payload = """
        [DELEGATION RETRY task_id=\(contract.id.uuidString) attempt=\(contract.retryCount)]
        Expected output format: \(contract.expectedFormat.rawValue)

        \(contract.prompt)

        When done, call report_result with task_id="\(contract.id.uuidString)".
        """

        _ = try? await store.sendMessage(
            from: contract.ownerPeerID,
            to: peer.id,
            content: payload,
            topic: "delegation"
        )
    }

    private func notifyOwner(contract: DelegationContract, message: String) async {
        let store = await CTermMCPServer.shared.store
        // Send a message back to the owner peer
        guard let ownerPeer = await store.getPeer(id: contract.ownerPeerID) else { return }
        let notification = """
        [DELEGATION UPDATE task_id=\(contract.id.uuidString) status=\(contract.status.rawValue)]
        Target: \(contract.targetPeerName)
        \(message)
        """
        // Use broadcast-style: send to owner's inbox
        _ = try? await store.sendMessage(
            from: contract.targetPeerID ?? contract.ownerPeerID,
            to: ownerPeer.id,
            content: notification,
            topic: "delegation-status"
        )
    }

    private func checkGroupCompletion(groupID: UUID, ownerPeerID: UUID) async {
        let agg = aggregatedResult(groupID: groupID)
        guard agg.isComplete else { return }

        let store = await CTermMCPServer.shared.store
        let summary = """
        [DELEGATION GROUP COMPLETE group_id=\(groupID.uuidString)]
        \(agg.summary)

        \(agg.combinedOutput)
        """
        _ = try? await store.sendMessage(
            from: ownerPeerID, // self-message to owner's inbox
            to: ownerPeerID,
            content: summary,
            topic: "delegation-group-complete"
        )
    }

    /// Remove completed/terminal contracts older than 10 minutes.
    func pruneStale() {
        let cutoff = Date().addingTimeInterval(-600)
        contracts = contracts.filter { !$0.value.status.isTerminal || $0.value.createdAt > cutoff }
    }
}
