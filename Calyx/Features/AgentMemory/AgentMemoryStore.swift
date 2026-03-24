// AgentMemoryStore.swift
// Calyx
//
// Persistent, project-scoped knowledge base for agent sessions.
// Stored at ~/.calyx/memories/{projectKey}.json — survives across sessions.
//
// Thread-safe via NSLock. MCP handlers call from background threads;
// the SwiftUI view calls from the main actor. Both paths are safe.

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.legato3.terminal", category: "AgentMemoryStore")

// MARK: - Model

struct MemoryEntry: Codable, Identifiable, Sendable {
    let id: UUID
    let key: String
    var value: String
    let createdAt: Date
    var updatedAt: Date
    var expiresAt: Date?   // nil = never expires

    init(key: String, value: String, ttlDays: Int?) {
        self.id = UUID()
        self.key = key
        self.value = value
        self.createdAt = Date()
        self.updatedAt = Date()
        self.expiresAt = ttlDays.map { Date().addingTimeInterval(Double($0) * 86400) }
    }

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return Date() > expiresAt
    }

    var age: String {
        let interval = Date().timeIntervalSince(updatedAt)
        switch interval {
        case ..<60:          return "just now"
        case ..<3600:        return "\(Int(interval / 60))m ago"
        case ..<86400:       return "\(Int(interval / 3600))h ago"
        default:             return "\(Int(interval / 86400))d ago"
        }
    }
}

// MARK: - Store

final class AgentMemoryStore: @unchecked Sendable {
    static let shared = AgentMemoryStore()

    private var lock = NSLock()
    // [projectKey: [key: entry]]
    private var data: [String: [String: MemoryEntry]] = [:]
    private let baseDir: URL

    private init() {
        baseDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".calyx/memories", isDirectory: true)
        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
    }

    // MARK: - Public API (thread-safe)

    /// Upsert a memory. Returns the saved entry.
    @discardableResult
    func remember(projectKey: String, key: String, value: String, ttlDays: Int?) -> MemoryEntry {
        lock.lock()
        defer { lock.unlock() }

        loadIfNeeded(projectKey)
        var entry: MemoryEntry
        if var existing = data[projectKey]?[key] {
            existing.value = value
            existing.updatedAt = Date()
            existing.expiresAt = ttlDays.map { Date().addingTimeInterval(Double($0) * 86400) }
            entry = existing
        } else {
            entry = MemoryEntry(key: key, value: value, ttlDays: ttlDays)
        }
        data[projectKey, default: [:]][key] = entry
        saveNoLock(projectKey)
        SessionAuditLogger.log(type: .memoryWritten, detail: "\(key): \(String(value.prefix(80)))")
        return entry
    }

    /// Full-text search across keys and values for this project.
    func recall(projectKey: String, query: String) -> [MemoryEntry] {
        lock.lock()
        defer { lock.unlock() }

        loadIfNeeded(projectKey)
        let entries = (data[projectKey] ?? [:]).values.filter { !$0.isExpired }
        let q = query.lowercased()
        if q.isEmpty { return Array(entries).sorted { $0.updatedAt > $1.updatedAt } }
        return entries
            .filter { $0.key.lowercased().contains(q) || $0.value.lowercased().contains(q) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Delete a memory by key. Returns true if it existed.
    @discardableResult
    func forget(projectKey: String, key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        loadIfNeeded(projectKey)
        guard data[projectKey]?[key] != nil else { return false }
        data[projectKey]?.removeValue(forKey: key)
        saveNoLock(projectKey)
        SessionAuditLogger.log(type: .memoryDeleted, detail: "Forgot: \(key)")
        return true
    }

    /// All non-expired memories for a project, newest first.
    func listAll(projectKey: String) -> [MemoryEntry] {
        lock.lock()
        defer { lock.unlock() }

        loadIfNeeded(projectKey)
        return (data[projectKey] ?? [:]).values
            .filter { !$0.isExpired }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: - Project Key

    /// Derive a stable project key from a working directory path.
    /// Tries git root first for a stable key across subdirectories.
    static func key(for workDir: String) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", workDir, "rev-parse", "--show-toplevel"]
        process.standardOutput = pipe
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0,
           let root = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
               .trimmingCharacters(in: .whitespacesAndNewlines),
           !root.isEmpty {
            return pathComponents(root)
        }
        return pathComponents(workDir)
    }

    // MARK: - Private

    private static func pathComponents(_ path: String) -> String {
        let parts = path.components(separatedBy: "/").filter { !$0.isEmpty }
        return parts.suffix(3).joined(separator: "_").replacingOccurrences(of: " ", with: "-")
    }

    /// Must be called with lock held.
    private func loadIfNeeded(_ projectKey: String) {
        guard data[projectKey] == nil else { return }
        let url = baseDir.appendingPathComponent("\(projectKey).json")
        guard let raw = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: MemoryEntry].self, from: raw) else {
            data[projectKey] = [:]
            return
        }
        data[projectKey] = decoded.filter { !$0.value.isExpired }
    }

    /// Must be called with lock held.
    private func saveNoLock(_ projectKey: String) {
        guard let entries = data[projectKey] else { return }
        let url = baseDir.appendingPathComponent("\(projectKey).json")
        let tmp = url.appendingPathExtension("tmp")
        guard let raw = try? JSONEncoder().encode(entries) else { return }
        do {
            try raw.write(to: tmp, options: .atomic)
            _ = try? FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } catch {
            logger.error("AgentMemoryStore: save failed for \(projectKey): \(error)")
        }
    }
}

// MARK: - Change notifications

extension Notification.Name {
    static let agentMemoryChanged = Notification.Name("com.legato3.terminal.agentMemoryChanged")
}
