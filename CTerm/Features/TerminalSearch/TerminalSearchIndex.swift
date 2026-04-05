// TerminalSearchIndex.swift
// CTerm
//
// SQLite FTS5-backed index of all terminal output.
// Lines are written by TerminalIndexer as they appear in each pane's viewport.
// Search is available to both the UI overlay (cmd+shift+F) and the MCP tool.

import Foundation
import SQLite3
import OSLog

private let logger = Logger(subsystem: "com.legato3.cterm", category: "TerminalSearchIndex")

// MARK: - Result

struct TerminalSearchResult: Identifiable, Sendable {
    let id: UUID
    let paneID: String
    let paneTitle: String
    let timestamp: Date
    let line: String

    init(paneID: String, paneTitle: String, timestamp: Date, line: String) {
        self.id = UUID()
        self.paneID = paneID
        self.paneTitle = paneTitle
        self.timestamp = timestamp
        self.line = line
    }
}

// MARK: - Index

/// Thread-safe SQLite FTS5 index. All database operations run on an internal
/// serial queue so callers don't need to worry about concurrency.
final class TerminalSearchIndex: @unchecked Sendable {
    static let shared = TerminalSearchIndex()

    private var db: OpaquePointer?
    private var insertStmt: OpaquePointer?
    private let queue = DispatchQueue(label: "com.legato3.cterm.search-index", qos: .utility)

    // SQLITE_TRANSIENT tells SQLite to copy the string before bind returns.
    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type?.self)

    private init() {
        queue.sync { self.setup() }
    }

    // MARK: - Setup

    private func setup() {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cterm")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("terminal-index.db").path

        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            logger.error("Failed to open terminal search index")
            return
        }
        sqlite3_exec(db, "PRAGMA journal_mode=WAL", nil, nil, nil)

        // FTS5 virtual table — `line` is indexed; other columns are unindexed metadata.
        let ddl = """
            CREATE VIRTUAL TABLE IF NOT EXISTS lines USING fts5(
                line,
                pane_id UNINDEXED,
                pane_title UNINDEXED,
                ts UNINDEXED,
                tokenize='unicode61 remove_diacritics 1'
            );
            CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT);
        """
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, ddl, nil, nil, &errMsg) != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "unknown"
            logger.error("DDL failed: \(msg)")
            sqlite3_free(errMsg)
        }

        let insertSQL = "INSERT INTO lines(line, pane_id, pane_title, ts) VALUES (?, ?, ?, ?)"
        sqlite3_prepare_v2(db, insertSQL, -1, &insertStmt, nil)

        logger.info("Terminal search index ready at \(path)")
    }

    // MARK: - Indexing

    /// Index a batch of new lines from a pane. Called from TerminalIndexer on a background queue.
    func index(lines: [String], paneID: String, paneTitle: String) {
        queue.async { [weak self] in
            self?.indexSync(lines: lines, paneID: paneID, paneTitle: paneTitle)
        }
    }

    private func indexSync(lines: [String], paneID: String, paneTitle: String) {
        guard let db, let stmt = insertStmt, !lines.isEmpty else { return }
        let ts = Date().timeIntervalSince1970

        sqlite3_exec(db, "BEGIN", nil, nil, nil)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            sqlite3_reset(stmt)
            sqlite3_bind_text(stmt, 1, trimmed, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, paneID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, paneTitle, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 4, ts)
            sqlite3_step(stmt)
        }
        sqlite3_exec(db, "COMMIT", nil, nil, nil)
    }

    // MARK: - Search

    /// Synchronous search — call off the main thread.
    func search(query: String, paneID: String? = nil, limit: Int = 60) -> [TerminalSearchResult] {
        queue.sync { self.searchSync(query: query, paneID: paneID, limit: limit) }
    }

    private func searchSync(query: String, paneID: String? = nil, limit: Int) -> [TerminalSearchResult] {
        guard let db, !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }

        // Build a safe FTS5 query. Wrap in quotes for phrase matching, but pass through
        // queries that already look like FTS5 expressions (contain : or AND/OR).
        let ftsQuery: String
        if query.contains(":") || query.uppercased().contains(" AND ") || query.uppercased().contains(" OR ") {
            ftsQuery = query
        } else {
            // Escape internal quotes and wrap as phrase
            let escaped = query.replacingOccurrences(of: "\"", with: "\"\"")
            ftsQuery = "\"\(escaped)\""
        }

        let sql: String
        if paneID != nil {
            sql = "SELECT line, pane_id, pane_title, ts FROM lines WHERE lines MATCH ? AND pane_id = ? ORDER BY ts DESC LIMIT ?"
        } else {
            sql = "SELECT line, pane_id, pane_title, ts FROM lines WHERE lines MATCH ? ORDER BY ts DESC LIMIT ?"
        }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, ftsQuery, -1, SQLITE_TRANSIENT)
        if let pid = paneID {
            sqlite3_bind_text(stmt, 2, pid, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 3, Int32(limit))
        } else {
            sqlite3_bind_int(stmt, 2, Int32(limit))
        }

        var results: [TerminalSearchResult] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let lineC = sqlite3_column_text(stmt, 0),
                  let pidC  = sqlite3_column_text(stmt, 1),
                  let ptC   = sqlite3_column_text(stmt, 2) else { continue }
            let line     = String(cString: lineC)
            let pid      = String(cString: pidC)
            let ptitle   = String(cString: ptC)
            let ts       = sqlite3_column_double(stmt, 3)
            results.append(TerminalSearchResult(
                paneID: pid,
                paneTitle: ptitle,
                timestamp: Date(timeIntervalSince1970: ts),
                line: line
            ))
        }
        return results
    }

    // MARK: - Maintenance

    /// Remove entries older than `days` to keep DB size bounded. Called once on startup.
    func pruneOldEntries(olderThan days: Double = 7) {
        queue.async { [weak self] in
            guard let db = self?.db else { return }
            let cutoff = Date().timeIntervalSince1970 - days * 86400
            sqlite3_exec(db, "DELETE FROM lines WHERE ts < \(cutoff)", nil, nil, nil)
        }
    }
}
