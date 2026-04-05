// TerminalBlockStore.swift
// CTerm
//
// Per-surface / per-tab store of terminal command blocks. Replaces the
// raw `[TerminalCommandBlock]` array that used to live on `Tab`.
// Blocks are transient — kept only in memory, capped at `maxBlocks`.

import Foundation

@MainActor
@Observable
final class TerminalBlockStore {
    /// Maximum number of blocks retained. Oldest entries evicted when exceeded.
    static let defaultCap = 100

    private(set) var all: [TerminalCommandBlock] = []
    private let cap: Int

    init(cap: Int = TerminalBlockStore.defaultCap) {
        self.cap = cap
    }

    /// Inserts a new block at the front (newest-first ordering) and enforces the cap.
    func append(_ block: TerminalCommandBlock) {
        all.insert(block, at: 0)
        evict(keepingLast: cap)
    }

    /// Replaces the block with the given id using the mutate closure.
    /// Returns true if a matching block was found and updated.
    @discardableResult
    func update(id: UUID, mutate: (inout TerminalCommandBlock) -> Void) -> Bool {
        guard let index = all.firstIndex(where: { $0.id == id }) else { return false }
        var block = all[index]
        mutate(&block)
        all[index] = block
        return true
    }

    /// Replaces the entire backing array (used by test helpers / restore).
    func replaceAll(with blocks: [TerminalCommandBlock]) {
        all = blocks
        evict(keepingLast: cap)
    }

    /// Returns the most recent `limit` blocks, newest-first.
    func recent(limit: Int = 10) -> [TerminalCommandBlock] {
        Array(all.prefix(limit))
    }

    func find(id: UUID) -> TerminalCommandBlock? {
        all.first(where: { $0.id == id })
    }

    /// Case-insensitive substring search across command text and output/error snippets.
    func search(query: String) -> [TerminalCommandBlock] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let needle = trimmed.lowercased()
        return all.filter { block in
            if let cmd = block.command?.lowercased(), cmd.contains(needle) { return true }
            if let out = block.outputSnippet?.lowercased(), out.contains(needle) { return true }
            if let err = block.errorSnippet?.lowercased(), err.contains(needle) { return true }
            return false
        }
    }

    /// Trims the store to keep at most `keepingLast` entries (newest-first).
    func evict(keepingLast: Int) {
        guard keepingLast >= 0 else { return }
        if all.count > keepingLast {
            all = Array(all.prefix(keepingLast))
        }
    }
}
