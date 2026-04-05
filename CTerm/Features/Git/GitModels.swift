// GitModels.swift
// CTerm
//
// Data models for git source control integration.

import Foundation

enum SidebarMode: Sendable {
    case tabs
    case changes
    case agentSession
    case agents
    case mesh
    case usage
    case context
    case fileChanges
    case taskQueue
    case delegations
    case agentMemory
    case testRunner
    case triggers
    case auditLog
    case agentPermissions
    case blocks
}

enum GitChangesState: Sendable {
    case notLoaded
    case notRepository
    case loading
    case loaded
    case error(String)
}

// MARK: - Git Status

enum GitFileStatus: String, Sendable {
    case modified = "M"
    case added = "A"
    case deleted = "D"
    case renamed = "R"
    case copied = "C"
    case untracked = "?"
    case unmerged = "U"
    case typeChanged = "T"
}

struct GitFileEntry: Identifiable, Equatable, Sendable {
    var id: String { "\(isStaged)-\(status.rawValue)-\(path)" }
    let path: String
    let origPath: String?
    let status: GitFileStatus
    let isStaged: Bool
    let renameScore: Int?
}

// MARK: - Commit Graph

struct GitCommit: Identifiable, Equatable, Sendable {
    let id: String              // full SHA
    let shortHash: String       // first 7 chars
    let message: String         // first line
    let author: String
    let relativeDate: String
    let parentIDs: [String]
    let graphPrefix: String     // git log --graph prefix string
}

struct CommitFileEntry: Identifiable, Equatable, Sendable {
    var id: String { "\(commitHash)-\(status.rawValue)-\(path)" }
    let commitHash: String
    let path: String
    let origPath: String?
    let status: GitFileStatus
}

// MARK: - Diff

enum DiffLineType: Sendable {
    case context
    case addition
    case deletion
    case hunkHeader
    case meta
}

struct DiffLine: Equatable, Sendable {
    let type: DiffLineType
    let text: String
    let oldLineNumber: Int?
    let newLineNumber: Int?
}

/// Structured representation of a single hunk. Used for per-hunk revert where we
/// need to reconstruct a valid patch for `git apply -R`. `bodyLines` contains the
/// raw lines between this hunk header and the next one (or the end of the diff) —
/// each line keeps its leading space / `+` / `-` / `\` marker.
struct DiffHunk: Equatable, Sendable {
    let header: String        // e.g. "@@ -10,4 +20,5 @@ fn context"
    let oldStart: Int
    let oldCount: Int
    let newStart: Int
    let newCount: Int
    let bodyLines: [String]   // body as-is, each with original prefix char
}

struct FileDiff: Equatable, Sendable {
    let path: String
    let lines: [DiffLine]
    let isBinary: Bool
    let isTruncated: Bool
    let hunks: [DiffHunk]

    init(path: String, lines: [DiffLine], isBinary: Bool, isTruncated: Bool, hunks: [DiffHunk] = []) {
        self.path = path
        self.lines = lines
        self.isBinary = isBinary
        self.isTruncated = isTruncated
        self.hunks = hunks
    }
}

enum DiffLoadState: Sendable {
    case loading
    case success(FileDiff)
    case error(String)
}

enum DiffSource: Sendable, Equatable {
    case unstaged(path: String, workDir: String)
    case staged(path: String, workDir: String)
    case commit(hash: String, path: String, workDir: String)
    case untracked(path: String, workDir: String)
    case allChanges(workDir: String)
}
