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
        let normalizedWorkDir = (workDir as NSString).standardizingPath
        self.id = UUID()
        self.path = Self.normalizePath(path, workDir: normalizedWorkDir)
        self.workDir = normalizedWorkDir
        self.peerID = peerID
        self.peerName = peerName
        self.timestamp = Date()
    }

    var fileName: String { (path as NSString).lastPathComponent }

    var relativePath: String {
        if (path as NSString).isAbsolutePath {
            return resolvedPath.hasPrefix(workDirPrefix)
                ? String(resolvedPath.dropFirst(workDirPrefix.count))
                : path
        }
        return path
    }

    var resolvedPath: String {
        if (path as NSString).isAbsolutePath {
            return (path as NSString).standardizingPath
        }
        return (workDir as NSString).appendingPathComponent(path)
    }

    private var workDirPrefix: String {
        workDir.hasSuffix("/") ? workDir : workDir + "/"
    }

    private static func normalizePath(_ path: String, workDir: String) -> String {
        let standardizedPath = (path as NSString).standardizingPath
        guard (standardizedPath as NSString).isAbsolutePath else { return standardizedPath }

        let workDirPrefix = workDir.hasSuffix("/") ? workDir : workDir + "/"
        if standardizedPath.hasPrefix(workDirPrefix) {
            return String(standardizedPath.dropFirst(workDirPrefix.count))
        }
        return standardizedPath
    }
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
        list.removeAll { $0.path == change.path && $0.workDir == change.workDir }
        list.append(change)
        changesByPeer[peerID] = list
    }

    func clearPeer(_ peerID: UUID) {
        changesByPeer.removeValue(forKey: peerID)
    }

    func clearAll() {
        changesByPeer.removeAll()
    }

    var trackedWorkDirs: [String] {
        let dirs = changesByPeer.values.flatMap { $0.map(\.workDir) }
        return Array(Set(dirs)).sorted()
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
