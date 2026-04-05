// BlockNavigatorFilter.swift
// CTerm
//
// Pure filter helpers for the Block Navigator sidebar. Kept free of UI / model
// dependencies so the filtering semantics can be unit-tested in isolation.

import Foundation

/// A `TerminalCommandBlock` paired with a lightweight descriptor of the tab it
/// originated on. Used as the display unit in the block navigator.
struct BlockWithTab: Identifiable, Sendable {
    let block: TerminalCommandBlock
    let tabID: UUID
    let tabTitle: String

    var id: UUID { block.id }
}

/// Scope of the navigator — "all tabs in this window" vs "just the current tab".
enum BlockNavigatorScope: Sendable, Equatable {
    case allTabs
    case currentTab
}

/// Exit-status filter chip state.
enum BlockStatusFilter: String, Sendable, CaseIterable, Identifiable {
    case all
    case succeeded
    case failed
    case running

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .succeeded: return "Succeeded"
        case .failed: return "Failed"
        case .running: return "Running"
        }
    }
}

/// Pure filter function. Applies scope, status filter, and full-text search
/// with AND-semantics. Case-insensitive substring match over command text,
/// output snippet, and error snippet.
enum BlockNavigatorFilter {
    static func apply(
        blocks: [BlockWithTab],
        scope: BlockNavigatorScope,
        currentTabID: UUID?,
        status: BlockStatusFilter,
        searchQuery: String
    ) -> [BlockWithTab] {
        let needle = searchQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return blocks.filter { entry in
            // Scope filter
            if scope == .currentTab {
                guard let current = currentTabID, entry.tabID == current else { return false }
            }

            // Status filter
            switch status {
            case .all:
                break
            case .succeeded:
                if entry.block.status != .succeeded { return false }
            case .failed:
                if entry.block.status != .failed { return false }
            case .running:
                if entry.block.status != .running { return false }
            }

            // Search filter
            if !needle.isEmpty {
                if !matches(block: entry.block, needle: needle) { return false }
            }

            return true
        }
    }

    private static func matches(block: TerminalCommandBlock, needle: String) -> Bool {
        if let cmd = block.command?.lowercased(), cmd.contains(needle) { return true }
        if let out = block.outputSnippet?.lowercased(), out.contains(needle) { return true }
        if let err = block.errorSnippet?.lowercased(), err.contains(needle) { return true }
        return false
    }
}
