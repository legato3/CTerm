// IPCAgentState.swift
// CTerm
//
// Observable singleton for peer agent visibility.
// Merges what was previously IPCAgentState + DelegationDashboardState into
// a single view of "other agents and their work."

import Foundation

// MARK: - AgentStatus

enum AgentStatus: Sendable {
    case active
    case idle
    case disconnected

    static func infer(from peer: Peer) -> AgentStatus {
        let age = Date().timeIntervalSince(peer.lastSeen)
        switch age {
        case ..<30:   return .active
        case ..<300:  return .idle
        default:      return .disconnected
        }
    }

    var label: String {
        switch self {
        case .active:       return "active"
        case .idle:         return "idle"
        case .disconnected: return "away"
        }
    }

    var color: String {
        switch self {
        case .active:       return "green"
        case .idle:         return "yellow"
        case .disconnected: return "gray"
        }
    }
}

@MainActor @Observable
final class IPCAgentState {
    static let shared = IPCAgentState()

    // MARK: - Peer State

    private(set) var peers: [Peer] = []
    private(set) var activityLog: [Message] = []
    private(set) var isRunning: Bool = false
    private(set) var port: Int = 0
    var unreadCount: Int = 0

    var isAgentsTabActive: Bool = false {
        didSet { if isAgentsTabActive { unreadCount = 0 } }
    }

    var lastWorkflow: [String]? = nil

    /// Number of active (non-disconnected) peers — shown as badge in tab bar.
    var activePeerCount: Int {
        peers.filter { AgentStatus.infer(from: $0) != .disconnected }.count
    }

    // MARK: - Delegation (merged from DelegationDashboardState)

    private(set) var delegationContracts: [DelegationContract] = []

    var activeDelegationCount: Int {
        delegationContracts.filter { !$0.status.isTerminal }.count
    }

    func refreshDelegations(_ snapshot: [DelegationContract]) {
        delegationContracts = snapshot.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Private

    private var seenMessageIDs: Set<UUID> = []
    private var pollTask: Task<Void, Never>?
    private static let maxLogSize = 500

    private init() {}

    // MARK: - Polling Lifecycle

    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func tick() {
        let server = CTermMCPServer.shared
        isRunning = server.isRunning
        port = server.port
        guard isRunning else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let freshPeers = await CTermMCPServer.shared.store.listPeers()
            let allMessages = await CTermMCPServer.shared.store.peekAllMessages()
            self.peers = freshPeers
            let newCount = self.append(allMessages)
            if !self.isAgentsTabActive && newCount > 0 {
                self.unreadCount += newCount
            }
        }
    }

    // MARK: - Log Management

    @discardableResult
    func append(_ messages: [Message]) -> Int {
        let new = messages.filter { !seenMessageIDs.contains($0.id) }
        for msg in new {
            seenMessageIDs.insert(msg.id)
            activityLog.append(msg)
            if msg.topic == "review-request" {
                NotificationCenter.default.post(name: .ctermIPCReviewRequested, object: nil)
            }
        }
        if activityLog.count > Self.maxLogSize {
            let excess = activityLog.count - Self.maxLogSize
            for msg in activityLog.prefix(excess) { seenMessageIDs.remove(msg.id) }
            activityLog.removeFirst(excess)
        }
        return new.count
    }

    func markRead() {
        unreadCount = 0
    }

    func clearLog() {
        activityLog.removeAll()
        unreadCount = 0
    }
}
