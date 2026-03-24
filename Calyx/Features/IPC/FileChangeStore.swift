// FileChangeStore.swift — tracks files modified by Claude agents during a session

import Foundation

struct TrackedFileChange: Identifiable, Sendable, Equatable {
    let id: UUID
    let path: String
    let workDir: String
    let peerID: UUID
    let peerName: String
    let timestamp: Date

    init(path: String, workDir: String, peerID: UUID, peerName: String) {
        self.id = UUID()
        self.path = path
        self.workDir = workDir
        self.peerID = peerID
        self.peerName = peerName
        self.timestamp = Date()
    }

    var fileName: String { (path as NSString).lastPathComponent }
    var relativePath: String { path }
}

@MainActor @Observable
final class FileChangeStore {
    static let shared = FileChangeStore()

    // keyed by peerID — most recent change per (peerID, path) pair
    private(set) var changesByPeer: [UUID: [TrackedFileChange]] = [:]

    private init() {}

    func report(path: String, workDir: String, peerID: UUID, peerName: String) {
        let change = TrackedFileChange(path: path, workDir: workDir, peerID: peerID, peerName: peerName)
        var list = changesByPeer[peerID] ?? []
        // deduplicate: remove older entry for same path if present
        list.removeAll { $0.path == path }
        list.append(change)
        changesByPeer[peerID] = list
    }

    func clearPeer(_ peerID: UUID) {
        changesByPeer.removeValue(forKey: peerID)
    }

    func clearAll() {
        changesByPeer.removeAll()
    }

    /// All unique (path, workDir) pairs across all peers, for aggregate diff.
    var allUniqueFiles: [(path: String, workDir: String)] {
        var seen = Set<String>()
        var result: [(path: String, workDir: String)] = []
        for changes in changesByPeer.values {
            for c in changes {
                let key = "\(c.workDir)/\(c.path)"
                if seen.insert(key).inserted {
                    result.append((path: c.path, workDir: c.workDir))
                }
            }
        }
        return result
    }
}
