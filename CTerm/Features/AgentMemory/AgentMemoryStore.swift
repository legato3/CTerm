// AgentMemoryStore.swift
// CTerm
//
// Persistent, project-scoped knowledge base for agent sessions.
// Stored at ~/.cterm/memories/{projectKey}.json — survives across sessions.
//
// Thread-safe via NSLock. MCP handlers call from background threads;
// the SwiftUI view calls from the main actor. Both paths are safe.

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.legato3.cterm", category: "AgentMemoryStore")

// MARK: - Memory Category

/// Typed categories for agent memories. Drives scoring, pruning, and retrieval filtering.
enum MemoryCategory: String, Codable, Sendable, CaseIterable {
    case projectFact       // architecture decisions, conventions, tech stack
    case userPreference    // formatting, workflow, tool preferences
    case recurringCommand  // build/test/lint commands that work
    case knownBroken       // fragile areas, known bugs, things to avoid
    case importantPath     // key files, config locations, entry points
    case buildConfig       // build/test/deploy commands and flags
    case handoff           // session handoff summaries

    /// Default TTL in days. nil = permanent.
    var defaultTTLDays: Int? {
        switch self {
        case .handoff:          return 7
        case .recurringCommand: return 30
        case .knownBroken:      return 14
        default:                return nil
        }
    }

    /// Base importance weight (0.0–1.0). Higher = harder to prune.
    var baseImportance: Double {
        switch self {
        case .projectFact:      return 0.9
        case .knownBroken:      return 0.85
        case .buildConfig:      return 0.8
        case .importantPath:    return 0.75
        case .userPreference:   return 0.7
        case .recurringCommand: return 0.6
        case .handoff:          return 0.5
        }
    }
}

// MARK: - Model

struct MemoryEntry: Codable, Identifiable, Sendable {
    let id: UUID
    let key: String
    var value: String
    let createdAt: Date
    var updatedAt: Date
    var expiresAt: Date?       // nil = never expires
    var category: MemoryCategory
    var importance: Double      // 0.0–1.0, drives pruning priority
    var confidence: Double      // 0.0–1.0, how certain we are this is correct
    var accessCount: Int        // how many times this was retrieved
    var lastAccessedAt: Date?   // last time recall returned this entry
    var source: MemorySource    // how this memory was created

    init(
        key: String,
        value: String,
        ttlDays: Int?,
        category: MemoryCategory = .projectFact,
        importance: Double = 0.5,
        confidence: Double = 0.8,
        source: MemorySource = .agentExplicit
    ) {
        self.id = UUID()
        self.key = key
        self.value = value
        self.createdAt = Date()
        self.updatedAt = Date()
        self.expiresAt = ttlDays.map { Date().addingTimeInterval(Double($0) * 86400) }
        self.category = category
        self.importance = min(max(importance, 0), 1)
        self.confidence = min(max(confidence, 0), 1)
        self.accessCount = 0
        self.lastAccessedAt = nil
        self.source = source
    }

    // Custom decoding to handle migration from old JSON without new fields
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        key = try container.decode(String.self, forKey: .key)
        value = try container.decode(String.self, forKey: .value)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
        category = (try? container.decode(MemoryCategory.self, forKey: .category)) ?? .projectFact
        importance = (try? container.decode(Double.self, forKey: .importance)) ?? 0.5
        confidence = (try? container.decode(Double.self, forKey: .confidence)) ?? 0.8
        accessCount = (try? container.decode(Int.self, forKey: .accessCount)) ?? 0
        lastAccessedAt = try? container.decode(Date.self, forKey: .lastAccessedAt)
        source = (try? container.decode(MemorySource.self, forKey: .source)) ?? .agentExplicit
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

    /// Composite score combining importance, recency, confidence, and access frequency.
    /// Higher = more valuable, less likely to be pruned.
    var relevanceScore: Double {
        let recencyDays = Date().timeIntervalSince(updatedAt) / 86400
        let recencyDecay = max(0, 1.0 - (recencyDays / 90.0)) // decays to 0 over 90 days
        let accessBoost = min(Double(accessCount) * 0.02, 0.2) // caps at +0.2
        return (importance * 0.4) + (recencyDecay * 0.3) + (confidence * 0.2) + (accessBoost * 0.1)
    }
}

/// How a memory was created — helps decide pruning aggressiveness.
enum MemorySource: String, Codable, Sendable {
    case agentExplicit     // agent called remember() directly
    case autoExtracted     // extracted from session audit automatically
    case userProvided      // user explicitly told the agent to remember
    case browserResearch   // extracted from browser research workflow
}

// MARK: - Store

final class AgentMemoryStore: @unchecked Sendable {
    static let shared = AgentMemoryStore()

    private var lock = NSLock()
    // [projectKey: [key: entry]]
    private var data: [String: [String: MemoryEntry]] = [:]
    private let baseDir: URL

    /// Max memories per project before compaction triggers.
    private static let compactionThreshold = 200
    /// Target count after compaction.
    private static let compactionTarget = 150

    private init() {
        baseDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cterm/memories", isDirectory: true)
        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
    }

    // MARK: - Public API (thread-safe)

    /// Upsert a memory. Returns the saved entry.
    @discardableResult
    func remember(
        projectKey: String,
        key: String,
        value: String,
        ttlDays: Int?,
        category: MemoryCategory = .projectFact,
        importance: Double = 0.5,
        confidence: Double = 0.8,
        source: MemorySource = .agentExplicit
    ) -> MemoryEntry {
        lock.lock()
        defer { lock.unlock() }

        loadIfNeeded(projectKey)

        // Reject junk: empty values, single-word values under 3 chars, or duplicates
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else {
            let entry = MemoryEntry(key: key, value: trimmed, ttlDays: ttlDays, category: category)
            return entry
        }

        var entry: MemoryEntry
        if var existing = data[projectKey]?[key] {
            existing.value = trimmed
            existing.updatedAt = Date()
            existing.expiresAt = ttlDays.map { Date().addingTimeInterval(Double($0) * 86400) }
            existing.category = category
            existing.importance = min(max(importance, 0), 1)
            existing.confidence = min(max(confidence, existing.confidence), 1) // confidence only goes up on update
            existing.source = source
            entry = existing
        } else {
            entry = MemoryEntry(
                key: key, value: trimmed, ttlDays: ttlDays,
                category: category, importance: importance,
                confidence: confidence, source: source
            )
        }
        data[projectKey, default: [:]][key] = entry

        // Auto-compact if over threshold
        if let count = data[projectKey]?.count, count > Self.compactionThreshold {
            compactNoLock(projectKey)
        }

        saveNoLock(projectKey)
        SessionAuditLogger.log(type: .memoryWritten, detail: "\(key): \(String(trimmed.prefix(80)))")
        return entry
    }

    /// Full-text search across keys and values for this project.
    /// Optionally filter by category. Results sorted by relevance score.
    func recall(projectKey: String, query: String, category: MemoryCategory? = nil) -> [MemoryEntry] {
        lock.lock()
        defer { lock.unlock() }

        loadIfNeeded(projectKey)
        var entries = (data[projectKey] ?? [:]).values.filter { !$0.isExpired }

        if let category {
            entries = entries.filter { $0.category == category }
        }

        let q = query.lowercased()
        if !q.isEmpty {
            entries = entries.filter {
                $0.key.lowercased().contains(q) || $0.value.lowercased().contains(q)
            }
        }

        // Bump access counts for returned entries
        let matchedKeys = entries.map(\.key)
        for key in matchedKeys {
            data[projectKey]?[key]?.accessCount += 1
            data[projectKey]?[key]?.lastAccessedAt = Date()
        }
        if !matchedKeys.isEmpty {
            saveNoLock(projectKey)
        }

        return entries.sorted { $0.relevanceScore > $1.relevanceScore }
    }

    /// Retrieve the top-N most relevant memories for a given intent/query.
    /// Uses relevance scoring to return only what matters.
    func relevantMemories(
        projectKey: String,
        intent: String,
        categories: [MemoryCategory]? = nil,
        limit: Int = 10
    ) -> [MemoryEntry] {
        lock.lock()
        defer { lock.unlock() }

        loadIfNeeded(projectKey)
        var entries = (data[projectKey] ?? [:]).values.filter { !$0.isExpired }

        if let categories {
            let catSet = Set(categories)
            entries = entries.filter { catSet.contains($0.category) }
        }

        // Score each entry against the intent
        let intentWords = Set(intent.lowercased().split(separator: " ").map(String.init))
        let scored: [(entry: MemoryEntry, score: Double)] = entries.map { entry in
            var score = entry.relevanceScore

            // Boost entries whose key or value overlaps with intent words
            let entryWords = Set(
                (entry.key + " " + entry.value).lowercased()
                    .split(separator: " ").map(String.init)
            )
            let overlap = Double(intentWords.intersection(entryWords).count)
            let intentCount = max(Double(intentWords.count), 1)
            score += (overlap / intentCount) * 0.3

            return (entry, score)
        }

        let topEntries = scored
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map(\.entry)

        // Bump access counts
        for entry in topEntries {
            data[projectKey]?[entry.key]?.accessCount += 1
            data[projectKey]?[entry.key]?.lastAccessedAt = Date()
        }
        if !topEntries.isEmpty {
            saveNoLock(projectKey)
        }

        return Array(topEntries)
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

    // MARK: - Compaction / Pruning

    /// Remove expired entries and prune lowest-scoring memories to stay under budget.
    /// Must be called with lock held.
    private func compactNoLock(_ projectKey: String) {
        guard var entries = data[projectKey] else { return }

        // 1. Remove expired
        let expiredKeys = entries.filter { $0.value.isExpired }.map(\.key)
        for key in expiredKeys {
            entries.removeValue(forKey: key)
        }

        // 2. If still over target, prune lowest-scoring entries
        if entries.count > Self.compactionTarget {
            let sorted = entries.values.sorted { $0.relevanceScore < $1.relevanceScore }
            let toPrune = sorted.prefix(entries.count - Self.compactionTarget)
            for entry in toPrune {
                // Never prune user-provided memories or very high importance
                guard entry.source != .userProvided, entry.importance < 0.95 else { continue }
                entries.removeValue(forKey: entry.key)
            }
        }

        data[projectKey] = entries
        logger.info("Compacted \(projectKey): \(expiredKeys.count) expired, \(entries.count) remaining")
    }

    /// Public compaction trigger — call periodically or on session end.
    func compact(projectKey: String) {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeeded(projectKey)
        compactNoLock(projectKey)
        saveNoLock(projectKey)
    }

    /// Prune all projects. Called on app launch to keep disk usage sane.
    func pruneAll() {
        lock.lock()
        defer { lock.unlock() }

        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: baseDir, includingPropertiesForKeys: nil)
            .filter({ $0.pathExtension == "json" }) else { return }

        for file in files {
            let projectKey = file.deletingPathExtension().lastPathComponent
            loadIfNeeded(projectKey)
            compactNoLock(projectKey)
            saveNoLock(projectKey)
        }
    }

    // MARK: - Agent Handoff

    /// Saves a session handoff summary so the next agent session can pick up where this one left off.
    @discardableResult
    func saveHandoff(projectKey: String, goal: String, stepsCompleted: Int, totalSteps: Int, filesChanged: [String], outcome: String) -> MemoryEntry {
        let summary = [
            "Goal: \(goal)",
            "Steps: \(stepsCompleted)/\(totalSteps)",
            filesChanged.isEmpty ? nil : "Files: \(filesChanged.prefix(10).joined(separator: ", "))",
            "Outcome: \(outcome)",
        ].compactMap { $0 }.joined(separator: "\n")

        return remember(
            projectKey: projectKey,
            key: "handoff/last-session",
            value: summary,
            ttlDays: 7,
            category: .handoff,
            importance: 0.5,
            confidence: 1.0,
            source: .autoExtracted
        )
    }

    /// Retrieves the most recent handoff summary, if any.
    func lastHandoff(projectKey: String) -> MemoryEntry? {
        recall(projectKey: projectKey, query: "handoff/last-session").first
    }

    // MARK: - Stats

    /// Memory stats for a project — useful for diagnostics.
    func stats(projectKey: String) -> MemoryStats {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeeded(projectKey)
        let entries = (data[projectKey] ?? [:]).values.filter { !$0.isExpired }
        let byCategory = Dictionary(grouping: entries, by: \.category)
            .mapValues(\.count)
        let avgScore = entries.isEmpty ? 0 : entries.map(\.relevanceScore).reduce(0, +) / Double(entries.count)
        return MemoryStats(
            totalCount: entries.count,
            byCategory: byCategory,
            averageRelevanceScore: avgScore,
            oldestUpdatedAt: entries.map(\.updatedAt).min(),
            newestUpdatedAt: entries.map(\.updatedAt).max()
        )
    }

    // MARK: - Project Key

    /// Derive a stable project key from a working directory path.
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

// MARK: - Stats Model

struct MemoryStats: Sendable {
    let totalCount: Int
    let byCategory: [MemoryCategory: Int]
    let averageRelevanceScore: Double
    let oldestUpdatedAt: Date?
    let newestUpdatedAt: Date?
}

// MARK: - Change notifications

extension Notification.Name {
    static let agentMemoryChanged = Notification.Name("com.legato3.cterm.agentMemoryChanged")
}
