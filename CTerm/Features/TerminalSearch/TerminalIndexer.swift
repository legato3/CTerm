// TerminalIndexer.swift
// CTerm
//
// One instance per tab. Polls the tab's terminal surfaces at regular intervals,
// diffs against the previously-seen viewport, and feeds genuinely new lines to
// TerminalSearchIndex. This captures content before it scrolls off-screen.

import Foundation
import GhosttyKit
import OSLog

private let logger = Logger(subsystem: "com.legato3.cterm", category: "TerminalIndexer")

@MainActor
final class TerminalIndexer {
    private weak var tab: Tab?
    private var pollTask: Task<Void, Never>?

    /// Lines seen at the end of the last poll (used as an anchor to find new lines).
    private var lastLines: [String] = []

    private static let pollInterval: UInt64 = 3_000_000_000  // 3 s

    init(tab: Tab) {
        self.tab = tab
    }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(nanoseconds: Self.pollInterval)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Polling

    private func tick() {
        guard let tab else { stop(); return }

        for surfaceID in tab.registry.allIDs {
            guard let controller = tab.registry.controller(for: surfaceID),
                  let surface = controller.surface,
                  let text = GhosttyFFI.surfaceReadViewportText(surface) else { continue }

            let currentLines = text
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            let newLines = findNewLines(previous: lastLines, current: currentLines)
            guard !newLines.isEmpty else { continue }

            lastLines = currentLines

            let paneID = surfaceID.uuidString
            let paneTitle = tab.title
            TerminalSearchIndex.shared.index(lines: newLines, paneID: paneID, paneTitle: paneTitle)
        }
    }

    // MARK: - Diffing

    /// Returns lines in `current` that appear after the last shared anchor with `previous`.
    /// If there's no overlap (fast scroll), returns all of `current`.
    private func findNewLines(previous: [String], current: [String]) -> [String] {
        guard !previous.isEmpty, !current.isEmpty else {
            return current
        }

        // Look for the last line of `previous` in `current`.
        // Work backwards through `previous` to find the best anchor.
        for anchor in previous.reversed().prefix(10) {
            if let idx = current.lastIndex(of: anchor) {
                let tail = Array(current[(current.index(after: idx))...])
                // Only return meaningful new content.
                return tail.isEmpty ? [] : tail
            }
        }

        // No overlap found — viewport scrolled entirely. Index everything new.
        // To avoid re-indexing stale content, only return lines not in lastLines.
        let lastSet = Set(previous.suffix(50))
        return current.filter { !lastSet.contains($0) }
    }
}
