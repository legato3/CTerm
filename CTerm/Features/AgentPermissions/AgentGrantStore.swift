// AgentGrantStore.swift
// CTerm
//
// Scope-aware grant cache. Sits in front of the trust-mode risk decision:
// if a matching grant exists for the current scope, the action auto-approves
// without surfacing the sheet.
//
// Scopes:
//   .once        — never recorded (just answers this one prompt)
//   .thisTask    — in-memory, keyed by session id, cleared when session ends
//   .thisRepo    — on-disk, keyed by repo hash, survives app restart
//   .thisSession — in-memory, cleared when app quits
//
// Hard-stops bypass this store entirely (checked by ApprovalGate first).

import Foundation
import Observation
import OSLog

private let logger = Logger(subsystem: "com.legato3.cterm", category: "AgentGrantStore")

@Observable
@MainActor
final class AgentGrantStore {

    static let shared = AgentGrantStore()

    // In-memory grants
    private var sessionGrants: Set<GrantKey> = []
    private var taskGrants: [UUID: Set<GrantKey>] = [:]

    // On-disk grants (repoKey → loaded file)
    private var repoGrants: [String: RepoGrantsFile] = [:]
    private var loadedRepos: Set<String> = []

    private init() {}

    // MARK: - Lookup

    /// Returns true if a grant for `key` is already in scope for `context`.
    func hasGrant(key: GrantKey, in context: GrantContext) -> Bool {
        if sessionGrants.contains(key) { return true }
        if let sid = context.sessionID, taskGrants[sid]?.contains(key) == true { return true }
        if let repoKey = context.repoKey {
            ensureRepoLoaded(repoKey)
            if let file = repoGrants[repoKey], file.grants.contains(where: { $0.key == key }) {
                return true
            }
        }
        return false
    }

    // MARK: - Record

    /// Store a grant at the requested scope. `.once` is a no-op (nothing recorded).
    func record(
        key: GrantKey,
        scope: ApprovalScope,
        context: GrantContext,
        repoPath: String?
    ) {
        switch scope {
        case .once:
            return

        case .thisTask:
            guard let sid = context.sessionID else {
                // Degrade: task scope without a session becomes session scope.
                sessionGrants.insert(key)
                return
            }
            taskGrants[sid, default: []].insert(key)

        case .thisSession:
            sessionGrants.insert(key)

        case .thisRepo:
            guard let repoKey = context.repoKey, let path = repoPath else {
                // No repo context: fall back to session scope.
                sessionGrants.insert(key)
                return
            }
            persistRepoGrant(repoKey: repoKey, repoPath: path, key: key)
        }

        logger.info("Grant recorded: \(key.category.rawValue)/\(key.riskTier.rawValue)/\(key.commandPrefix) scope=\(scope.rawValue)")
    }

    // MARK: - Revoke

    /// Remove every session- and task-scoped grant. Repo grants on disk are untouched.
    func revokeAllSessionGrants() {
        sessionGrants.removeAll()
        taskGrants.removeAll()
        logger.info("All session/task grants revoked")
    }

    /// Clear grants for one specific task (session).
    func revokeTaskGrants(sessionID: UUID) {
        taskGrants.removeValue(forKey: sessionID)
    }

    /// Wipe every repo grant file on disk.
    func revokeAllRepoGrants() {
        repoGrants.removeAll()
        loadedRepos.removeAll()
        Task { await GrantsPersistence.shared.deleteAll() }
        logger.info("All repo grants revoked")
    }

    /// Wipe one repo's grants both in-memory and on disk.
    func revokeRepoGrants(repoKey: String) {
        repoGrants.removeValue(forKey: repoKey)
        loadedRepos.remove(repoKey)
        Task { await GrantsPersistence.shared.delete(repoKey: repoKey) }
    }

    // MARK: - Inspection (used by UI / tests)

    var sessionGrantCount: Int { sessionGrants.count }
    var taskGrantCount: Int { taskGrants.values.reduce(0) { $0 + $1.count } }
    var repoGrantCount: Int { repoGrants.values.reduce(0) { $0 + $1.grants.count } }

    // MARK: - Private

    private func ensureRepoLoaded(_ repoKey: String) {
        guard !loadedRepos.contains(repoKey) else { return }
        loadedRepos.insert(repoKey)
        if let file = loadRepoGrantFromDisk(repoKey: repoKey) {
            repoGrants[repoKey] = file
        }
    }

    private func persistRepoGrant(repoKey: String, repoPath: String, key: GrantKey) {
        var file = repoGrants[repoKey] ?? RepoGrantsFile(repoKey: repoKey, repoPath: repoPath)
        if !file.grants.contains(where: { $0.key == key }) {
            file.grants.append(RepoGrantEntry(key: key))
        }
        repoGrants[repoKey] = file
        loadedRepos.insert(repoKey)
        let snapshot = file
        Task { await GrantsPersistence.shared.save(snapshot) }
    }

    private func loadRepoGrantFromDisk(repoKey: String) -> RepoGrantsFile? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let url = home
            .appendingPathComponent(".cterm/grants", isDirectory: true)
            .appendingPathComponent("\(repoKey).json")
        guard let data = try? Data(contentsOf: url) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(RepoGrantsFile.self, from: data)
        } catch {
            logger.warning("Failed to decode grants for \(repoKey): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Test hook

    #if DEBUG
    func _resetForTesting() {
        sessionGrants.removeAll()
        taskGrants.removeAll()
        repoGrants.removeAll()
        loadedRepos.removeAll()
    }
    #endif
}
