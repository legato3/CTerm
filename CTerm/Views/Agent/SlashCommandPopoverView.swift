// SlashCommandPopoverView.swift
// CTerm
//
// Warp-style slash-command picker. Lists matching built-in commands with
// signature and description. Supports arrow-key navigation, Enter select,
// Esc dismiss.

import SwiftUI

@MainActor
struct SlashCommandPopoverView: View {
    let commands: [SlashCommand]
    let coordinator: SlashPopoverCoordinator
    let onSelect: (SlashCommand) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if commands.isEmpty {
                Text("No matching commands")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(10)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(commands.enumerated()), id: \.element.id) { index, cmd in
                            row(for: cmd, isSelected: index == coordinator.selectedIndex)
                                .contentShape(Rectangle())
                                .onTapGesture { onSelect(cmd) }
                        }
                    }
                }
                .frame(maxHeight: 280)
            }
        }
        .frame(width: 300)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private func row(for cmd: SlashCommand, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text("/" + cmd.name)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.primary)

                if !cmd.args.isEmpty {
                    Text(argSuffix(for: cmd))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary.opacity(0.7))
                }

                Spacer()
            }

            Text(cmd.description)
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
    }

    private func argSuffix(for cmd: SlashCommand) -> String {
        cmd.args.map { "<\($0.name)>" }.joined(separator: " ")
    }
}
