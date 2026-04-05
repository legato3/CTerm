// AttachedBlockChipsView.swift
// CTerm
//
// Warp-style chips row for blocks attached to the next agent prompt.
// Mounted directly above the compose text input — hidden when empty.

import SwiftUI

@MainActor
struct AttachedBlockChipsView: View {
    let blocks: [TerminalCommandBlock]
    let onDetach: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(blocks) { block in
                    chip(for: block)
                }
            }
            .padding(.horizontal, 10)
        }
        .frame(height: 24)
    }

    @ViewBuilder
    private func chip(for block: TerminalCommandBlock) -> some View {
        HStack(spacing: 4) {
            Text(glyph(for: block))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(color(for: block))

            Text(truncate(block.titleText, to: 30))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Button {
                onDetach(block.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.accentColor.opacity(0.12), in: Capsule())
    }

    private func glyph(for block: TerminalCommandBlock) -> String {
        switch block.status {
        case .running: return "…"
        case .succeeded: return "✓"
        case .failed: return "✗"
        }
    }

    private func color(for block: TerminalCommandBlock) -> Color {
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
}
