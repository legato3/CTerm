// PaneUsageMonitor.swift
// Calyx
//
// Phase 9: Token Budget HUD — per-tab polling monitor that scrapes Claude's
// context-window status lines from terminal viewport text, writing results
// to the shared PaneUsageStore so TokenHUDView can render them.

import Foundation
import GhosttyKit
import OSLog

private let logger = Logger(subsystem: "com.legato3.terminal", category: "PaneUsageMonitor")

// MARK: - PaneUsageSnapshot

/// Observed context-window usage for a single terminal pane.
struct PaneUsageSnapshot: Sendable {
    /// Context window fraction 0.0–1.0, nil if not yet detected.
    var contextFraction: Double?
    /// Raw input token count if detected (e.g. "90,000 / 200,000").
    var tokensUsed: Int?
    var tokensTotal: Int?
    var updatedAt: Date = .now
}

// MARK: - PaneUsageStore

/// Shared observable store: `snapshots[paneID]` updated by PaneUsageMonitor.
@MainActor @Observable
final class PaneUsageStore {
    static let shared = PaneUsageStore()
    var snapshots: [UUID: PaneUsageSnapshot] = [:]
    private init() {}
}

// MARK: - PaneUsageMonitor

/// Per-tab background monitor. Polls terminal viewport text every 5 seconds,
/// parses Claude's context-window lines, and writes to PaneUsageStore.
@MainActor
final class PaneUsageMonitor {

    private weak var tab: Tab?
    private var pollTask: Task<Void, Never>?
    private static let pollIntervalNs: UInt64 = 5_000_000_000   // 5 s

    // Lines Claude Code shows for context warnings / usage info.
    // Scan last 40 lines (enough to catch a status update without wasting CPU).
    private static let scanLineCount = 40

    init(tab: Tab) {
        self.tab = tab
    }

    func start() {
        guard pollTask == nil else { return }
        logger.debug("PaneUsageMonitor started for tab \(self.tab?.id.uuidString ?? "?")")
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(nanoseconds: Self.pollIntervalNs)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        logger.debug("PaneUsageMonitor stopped for tab \(self.tab?.id.uuidString ?? "?")")
    }

    // MARK: - Poll Tick

    private func tick() {
        guard let tab else { stop(); return }

        for surfaceID in tab.registry.allIDs {
            guard let controller = tab.registry.controller(for: surfaceID),
                  let surface = controller.surface,
                  let text = GhosttyFFI.surfaceReadViewportText(surface)
            else { continue }

            let tail = lastLines(text, count: Self.scanLineCount)
            var snap = PaneUsageStore.shared.snapshots[surfaceID] ?? PaneUsageSnapshot()
            snap.updatedAt = .now

            if let (used, total) = parseTokenCounts(from: tail) {
                snap.tokensUsed = used
                snap.tokensTotal = total
                snap.contextFraction = total > 0 ? Double(used) / Double(total) : snap.contextFraction
            } else if let pct = parseContextPercent(from: tail) {
                snap.contextFraction = pct
            }

            PaneUsageStore.shared.snapshots[surfaceID] = snap
        }
    }

    // MARK: - Text Helpers

    private func lastLines(_ text: String, count: Int) -> String {
        let lines = text.components(separatedBy: "\n")
        return lines.suffix(count).joined(separator: "\n")
    }

    // MARK: - Parsers

    /// Parses "90,000 / 200,000 tokens" or "90000/200000" style token counts.
    private func parseTokenCounts(from text: String) -> (used: Int, total: Int)? {
        // e.g. "90,000 / 200,000" or "90000/200000"
        let pattern = #"(\d[\d,]*)\s*/\s*(\d[\d,]*)\s*(?:tokens?)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        guard let usedRange = Range(match.range(at: 1), in: text),
              let totalRange = Range(match.range(at: 2), in: text) else { return nil }
        let usedStr = text[usedRange].replacingOccurrences(of: ",", with: "")
        let totalStr = text[totalRange].replacingOccurrences(of: ",", with: "")
        guard let used = Int(usedStr), let total = Int(totalStr), total > 0, used <= total else { return nil }
        // Sanity check: reasonable token counts (100 – 2M)
        guard used >= 100, total >= 1000, total <= 2_000_000 else { return nil }
        return (used, total)
    }

    /// Parses percentage near context-related keywords.
    /// Matches: "context window usage: 73%", "73% full", "73% of context", etc.
    private func parseContextPercent(from text: String) -> Double? {
        // Look for context + percentage within 80 chars
        let lowered = text.lowercased()

        // Strategy 1: "context" then a % within the same or next 80 chars
        if let ctxRange = lowered.range(of: "context") {
            let searchStart = ctxRange.lowerBound
            let searchEnd = lowered.index(ctxRange.lowerBound, offsetBy: 80, limitedBy: lowered.endIndex) ?? lowered.endIndex
            let window = String(lowered[searchStart..<searchEnd])
            if let pct = extractPercent(from: window) { return pct }
        }

        // Strategy 2: percentage then "context" or "full" within 40 chars
        let pattern = #"(\d{1,3})%\s*(?:full|of context|context)"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let range = NSRange(text.startIndex..., in: text)
            if let m = regex.firstMatch(in: lowered, range: range),
               let r = Range(m.range(at: 1), in: lowered),
               let pct = Double(lowered[r]) {
                return pct / 100.0
            }
        }

        return nil
    }

    private func extractPercent(from text: String) -> Double? {
        let pattern = #"(\d{1,3})%"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range(at: 1), in: text),
              let val = Double(text[r]),
              val >= 0, val <= 100
        else { return nil }
        return val / 100.0
    }
}
