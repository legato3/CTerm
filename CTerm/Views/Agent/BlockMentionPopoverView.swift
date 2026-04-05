// BlockMentionPopoverView.swift
// CTerm
//
// Warp-style @block mention picker. Lists recent command blocks with
// exit-status glyph, truncated command, relative time, and a dim output
// preview. Supports arrow-key navigation, Enter select, Esc dismiss.

import SwiftUI

@MainActor
struct BlockMentionPopoverView: View {
    let blocks: [TerminalCommandBlock]
    let coordinator: BlockMentionPopoverCoordinator
    let onSelect: (TerminalCommandBlock) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if blocks.isEmpty {
                Text("No matching blocks")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(10)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                            row(for: block, isSelected: index == coordinator.selectedIndex)
                                .contentShape(Rectangle())
                                .onTapGesture { onSelect(block) }
                        }
                    }
                }
                .frame(maxHeight: 280)
            }
        }
        .frame(width: 360)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private func row(for block: TerminalCommandBlock, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(statusGlyph(for: block))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(statusColor(for: block))
                    .frame(width: 12)

                Text(truncate(block.titleText, to: 60))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                Text(relativeTime(for: block.startedAt))
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            if let preview = outputPreview(for: block) {
                Text(preview)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .lineLimit(2)
                    .padding(.leading, 18)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
    }

    private func statusGlyph(for block: TerminalCommandBlock) -> String {
        switch block.status {
        case .running: return "…"
        case .succeeded: return "✓"
        case .failed: return "✗"
        }
    }

    private func statusColor(for block: TerminalCommandBlock) -> Color {
        switch block.status {
        case .running: return .secondary
        case .succeeded: return .green
        case .failed: return .red
        }
    }

    private func truncate(_ s: String, to length: Int) -> String {
        if s.count <= length { return s }
        return String(s.prefix(length)) + "…"
    }

    private func outputPreview(for block: TerminalCommandBlock) -> String? {
        guard let snippet = block.primarySnippet else { return nil }
        let lines = snippet
            .split(separator: "\n", omittingEmptySubsequences: true)
            .prefix(2)
            .joined(separator: " · ")
        let trimmed = lines.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : truncate(trimmed, to: 100)
    }

    private func relativeTime(for date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }
}

/// Helper for computing a short block ID (first 8 hex chars of UUID) used
/// in the `@block:<shortID>` prompt token.
@MainActor
enum BlockMentionToken {
    static let prefix = "@block:"

    static func shortID(for uuid: UUID) -> String {
        // UUID's canonical string: first 8 chars up to the first hyphen.
        let full = uuid.uuidString.lowercased()
        return String(full.prefix(8))
    }

    static func token(for uuid: UUID) -> String {
        prefix + shortID(for: uuid)
    }

    /// Scans text for `@block:<shortID>` tokens and returns the set of short IDs.
    static func extractShortIDs(from text: String) -> [String] {
        var out: [String] = []
        var remainder = Substring(text)
        while let range = remainder.range(of: prefix) {
            let afterPrefix = remainder[range.upperBound...]
            let shortID = afterPrefix.prefix { ch in
                ch.isHexDigit
            }
            if shortID.count >= 4 {
                out.append(String(shortID).lowercased())
            }
            remainder = afterPrefix.dropFirst(shortID.count)
        }
        return out
    }

    /// Removes all `@block:<shortID>` tokens from the text and collapses whitespace.
    static func stripTokens(from text: String) -> String {
        var result = ""
        var remainder = Substring(text)
        while let range = remainder.range(of: prefix) {
            result += remainder[..<range.lowerBound]
            let afterPrefix = remainder[range.upperBound...]
            let shortID = afterPrefix.prefix { ch in
                ch.isHexDigit
            }
            remainder = afterPrefix.dropFirst(shortID.count)
        }
        result += remainder
        // Collapse any runs of 2+ spaces left behind.
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
