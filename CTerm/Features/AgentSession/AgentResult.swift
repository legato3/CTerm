// AgentResult.swift
// CTerm
//
// Post-run summary for an AgentSession. Feeds ActiveAISuggestionEngine,
// handoff memory, and the user-facing completion panel.

import Foundation

struct NextAction: Sendable, Codable, Identifiable {
    let id: UUID
    let label: String              // short user-visible prompt
    let prompt: String             // full intent to pass into a follow-up session
    let confidence: Double         // 0–1

    init(label: String, prompt: String, confidence: Double = 0.7) {
        self.id = UUID()
        self.label = label
        self.prompt = prompt
        self.confidence = confidence
    }
}

/// A single file the agent touched during a session. Replaces the old
/// `[String]` list so the inline diff review panel can render per-file
/// hunks, stats and revert controls without re-querying git for each row.
struct ChangedFile: Sendable, Codable, Hashable, Identifiable {
    enum Status: String, Sendable, Codable {
        case added
        case modified
        case deleted
        case renamed
        case untracked
    }

    var id: String { path }
    let path: String
    let status: Status
    let additions: Int
    let deletions: Int
    let oldPath: String?  // for renames

    init(path: String, status: Status, additions: Int = 0, deletions: Int = 0, oldPath: String? = nil) {
        self.path = path
        self.status = status
        self.additions = additions
        self.deletions = deletions
        self.oldPath = oldPath
    }
}

struct AgentResult: Sendable, Codable {
    let summary: String
    var filesChanged: [ChangedFile]
    let nextActions: [NextAction]
    let durationMs: Int
    let handoffMemoryKey: String?  // key into AgentMemoryStore if handoff was written
    let exitStatus: ExitStatus

    enum ExitStatus: String, Sendable, Codable {
        case succeeded
        case failed
        case cancelled
        case partial   // some steps succeeded, some did not
    }

    /// Convenience facade for call sites that still want the bare path list.
    var filesChangedPaths: [String] { filesChanged.map(\.path) }

    init(
        summary: String,
        filesChanged: [ChangedFile],
        nextActions: [NextAction],
        durationMs: Int,
        handoffMemoryKey: String?,
        exitStatus: ExitStatus
    ) {
        self.summary = summary
        self.filesChanged = filesChanged
        self.nextActions = nextActions
        self.durationMs = durationMs
        self.handoffMemoryKey = handoffMemoryKey
        self.exitStatus = exitStatus
    }

    // MARK: - Codable (lenient filesChanged)

    private enum CodingKeys: String, CodingKey {
        case summary, filesChanged, nextActions, durationMs, handoffMemoryKey, exitStatus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.summary = try container.decode(String.self, forKey: .summary)
        self.nextActions = try container.decode([NextAction].self, forKey: .nextActions)
        self.durationMs = try container.decode(Int.self, forKey: .durationMs)
        self.handoffMemoryKey = try container.decodeIfPresent(String.self, forKey: .handoffMemoryKey)
        self.exitStatus = try container.decode(ExitStatus.self, forKey: .exitStatus)

        // Lenient decode: try [ChangedFile] first (new format), fall back to
        // [String] (old format) and map each to a .modified ChangedFile.
        if let typed = try? container.decode([ChangedFile].self, forKey: .filesChanged) {
            self.filesChanged = typed
        } else if let paths = try? container.decode([String].self, forKey: .filesChanged) {
            self.filesChanged = paths.map {
                ChangedFile(path: $0, status: .modified, additions: 0, deletions: 0, oldPath: nil)
            }
        } else {
            self.filesChanged = []
        }
    }
}
