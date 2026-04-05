// SessionFactExtractor.swift
// CTerm
//
// Extracts durable facts from completed agent sessions.
// Runs at session end (peer disconnect or app quit) to mine the audit log
// for patterns worth remembering: successful commands, error patterns,
// file paths that came up repeatedly, etc.
//
// Skeptical by design — only stores facts that meet confidence thresholds.

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.legato3.cterm", category: "SessionFactExtractor")

enum SessionFactExtractor {

    // MARK: - Public API

    /// Extract and store durable facts from the current session's audit log.
    /// Call this when an agent peer disconnects or the session ends.
    @MainActor
    static func extractFromCurrentSession(projectKey: String) {
        let events = SessionAuditLogger.shared.events
        guard events.count >= 3 else { return } // too few events to learn from

        let store = AgentMemoryStore.shared
        var stored = 0

        // 1. Successful build/test commands
        stored += extractSuccessfulCommands(from: events, projectKey: projectKey, store: store)

        // 2. Recurring error patterns (known broken areas)
        stored += extractErrorPatterns(from: events, projectKey: projectKey, store: store)

        // 3. Frequently referenced file paths
        stored += extractImportantPaths(projectKey: projectKey, store: store)

        if stored > 0 {
            logger.info("SessionFactExtractor: stored \(stored) facts for \(projectKey)")
        }
    }

    // MARK: - Command Extraction

    /// Finds commands that were injected and not followed by errors.
    /// If a command appears 2+ times successfully, it's worth remembering.
    private static func extractSuccessfulCommands(
        from events: [AuditEvent],
        projectKey: String,
        store: AgentMemoryStore
    ) -> Int {
        // Collect command events and error events with timestamps
        let commands = events.filter { $0.type == .commandInjected }
        let errors = events.filter { $0.type == .errorRouted }
        let errorTimestamps = errors.map(\.timestamp)

        // A command is "successful" if no error occurred within 10 seconds after it
        var successfulCommands: [String: Int] = [:]
        for cmd in commands {
            let cmdText = cmd.detail.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cmdText.isEmpty, cmdText.count > 3 else { continue }

            let hadNearbyError = errorTimestamps.contains { errorTime in
                let delta = errorTime.timeIntervalSince(cmd.timestamp)
                return delta > 0 && delta < 10
            }

            if !hadNearbyError {
                successfulCommands[cmdText, default: 0] += 1
            }
        }

        var stored = 0
        for (cmd, count) in successfulCommands where count >= 2 {
            // Classify the command
            let category: MemoryCategory
            let key: String
            if cmd.contains("test") || cmd.contains("xcodebuild") && cmd.contains("test") {
                category = .buildConfig
                key = "auto/test-command"
            } else if cmd.contains("build") || cmd.contains("xcodebuild") || cmd.contains("make") {
                category = .buildConfig
                key = "auto/build-command"
            } else if cmd.contains("lint") || cmd.contains("swiftlint") || cmd.contains("eslint") {
                category = .buildConfig
                key = "auto/lint-command"
            } else {
                category = .recurringCommand
                key = "auto/cmd/\(String(cmd.prefix(40)).replacingOccurrences(of: " ", with: "-"))"
            }

            store.remember(
                projectKey: projectKey,
                key: key,
                value: cmd,
                ttlDays: category.defaultTTLDays,
                category: category,
                importance: 0.7,
                confidence: min(0.6 + Double(count) * 0.1, 0.95),
                source: .autoExtracted
            )
            stored += 1
        }
        return stored
    }

    // MARK: - Error Pattern Extraction

    /// If the same error pattern appears 2+ times, store it as a known broken area.
    private static func extractErrorPatterns(
        from events: [AuditEvent],
        projectKey: String,
        store: AgentMemoryStore
    ) -> Int {
        let errors = events.filter { $0.type == .errorRouted }
        guard errors.count >= 2 else { return 0 }

        // Normalize error details to find patterns
        var patterns: [String: Int] = [:]
        for error in errors {
            let normalized = normalizeError(error.detail)
            guard normalized.count >= 10 else { continue }
            patterns[normalized, default: 0] += 1
        }

        var stored = 0
        for (pattern, count) in patterns where count >= 2 {
            let key = "auto/known-issue/\(String(pattern.prefix(50)).replacingOccurrences(of: " ", with: "-"))"
            store.remember(
                projectKey: projectKey,
                key: key,
                value: "Recurring error (\(count)x): \(pattern)",
                ttlDays: MemoryCategory.knownBroken.defaultTTLDays,
                category: .knownBroken,
                importance: 0.8,
                confidence: min(0.5 + Double(count) * 0.15, 0.9),
                source: .autoExtracted
            )
            stored += 1
        }
        return stored
    }

    /// Strip line numbers, timestamps, and UUIDs to find the core error pattern.
    private static func normalizeError(_ detail: String) -> String {
        var s = detail
        // Remove line:col references
        s = s.replacingOccurrences(of: #":\d+:\d+"#, with: ":_:_", options: .regularExpression)
        // Remove UUIDs
        s = s.replacingOccurrences(
            of: #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"#,
            with: "<uuid>", options: .regularExpression
        )
        // Remove timestamps
        s = s.replacingOccurrences(
            of: #"\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}"#,
            with: "<time>", options: .regularExpression
        )
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Important Path Extraction

    /// Checks file changes reported during the session for frequently touched paths.
    @MainActor
    private static func extractImportantPaths(
        projectKey: String,
        store: AgentMemoryStore
    ) -> Int {
        let allChanges = FileChangeStore.shared.changesByPeer.values.flatMap { $0 }
        guard allChanges.count >= 3 else { return 0 }

        // Count directory frequency
        var dirCounts: [String: Int] = [:]
        for change in allChanges {
            let dir = (change.path as NSString).deletingLastPathComponent
            guard !dir.isEmpty else { continue }
            dirCounts[dir, default: 0] += 1
        }

        var stored = 0
        for (dir, count) in dirCounts where count >= 3 {
            let key = "auto/hot-dir/\(dir.replacingOccurrences(of: "/", with: "_"))"
            store.remember(
                projectKey: projectKey,
                key: key,
                value: "Frequently modified directory (\(count) changes this session): \(dir)",
                ttlDays: 14,
                category: .importantPath,
                importance: 0.6,
                confidence: min(0.5 + Double(count) * 0.1, 0.85),
                source: .autoExtracted
            )
            stored += 1
        }
        return stored
    }
}

// MARK: - Examples of what to store vs ignore
//
// STORE (durable, project-specific, actionable):
//   ✓ "test-command" → "xcodebuild -scheme CTermTests test"
//   ✓ "auth-system" → "Uses JWT tokens, refresh handled in AuthManager.swift"
//   ✓ "avoid-force-unwrap" → "No force unwraps in production code per AGENTS.md"
//   ✓ "build-requires" → "Must run xcodegen generate before xcodebuild"
//   ✓ "fragile/split-tree" → "SplitTree mutations must replace values, not edit in place"
//
// IGNORE (ephemeral, obvious, or too noisy):
//   ✗ "current-branch" → "feature/login" (changes constantly, git provides this)
//   ✗ "file-contents" → <entire file dump> (too large, stale immediately)
//   ✗ "user-said-hi" → "User greeted me" (not actionable)
//   ✗ "ran-ls" → "ls -la output..." (ephemeral command output)
//   ✗ "error-at-3pm" → "Got a 404" (too specific to a moment)
