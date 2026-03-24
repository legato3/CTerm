// SessionAuditView.swift
// Calyx
//
// Sidebar panel for the session audit log — timeline, summary stats, and export.

import SwiftUI

struct SessionAuditView: View {
    @State private var logger = SessionAuditLogger.shared
    @State private var filter: AuditFilter = .all

    private var filtered: [AuditEvent] {
        let all = logger.events.reversed() as ReversedCollection
        if filter == .all { return Array(all) }
        return all.filter { $0.type.filterGroup == filter }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            summaryBar
            Divider().opacity(0.3)
            filterRow
            Divider().opacity(0.3)

            if filtered.isEmpty {
                emptyState
            } else {
                timeline
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Label("Session Log", systemImage: "clock.arrow.circlepath")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .tracking(0.5)
            Spacer()
            Text("\(logger.events.count) events")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.tertiary)
            Button(action: exportMarkdown) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Copy session log as Markdown")
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    // MARK: - Summary bar

    private var summaryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip("\(logger.commandCount)", icon: "terminal",              color: .blue,   label: "cmds")
                chip("\(logger.errorCount)",   icon: "exclamationmark.triangle", color: .orange, label: "errors")
                chip("\(logger.memoryCount)",  icon: "brain.head.profile",   color: .purple, label: "memories")
                chip("\(logger.testRunCount)", icon: "testtube.2",           color: .teal,   label: "tests")
                chip("\(logger.taskCount)",    icon: "checkmark.circle",     color: .green,  label: "tasks")
                chip("\(logger.checkpointCount)", icon: "arrow.triangle.branch", color: .yellow, label: "checkpoints")
            }
            .padding(.horizontal, 10)
        }
        .padding(.vertical, 6)
    }

    private func chip(_ count: String, icon: String, color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 9))
            Text(count).font(.system(size: 11, weight: .semibold, design: .rounded))
            Text(label).font(.system(size: 9, design: .rounded))
        }
        .foregroundStyle(color.opacity(0.9))
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.12)))
    }

    // MARK: - Filter row

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(AuditFilter.allCases, id: \.self) { f in
                    Button(action: { filter = f }) {
                        Text(f.rawValue)
                            .font(.system(size: 10, weight: filter == f ? .semibold : .regular, design: .rounded))
                            .foregroundStyle(filter == f ? .primary : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(filter == f ? Color.white.opacity(0.12) : .clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
        }
        .padding(.vertical, 5)
    }

    // MARK: - Timeline

    private var timeline: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filtered) { event in
                    AuditEventRow(event: event)
                    Divider().opacity(0.15).padding(.leading, 40)
                }
            }
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("No events yet")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Text("Commands, errors, memory writes,\nand agent connections will appear here.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - Export

    private func exportMarkdown() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(logger.markdownExport(), forType: .string)
    }
}

// MARK: - Event row

private struct AuditEventRow: View {
    let event: AuditEvent

    private var iconColor: Color {
        switch event.type.color {
        case "blue":    return .blue
        case "orange":  return .orange
        case "purple":  return .purple
        case "teal":    return .teal
        case "green":   return .green
        case "yellow":  return .yellow
        default:        return .secondary
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 24, height: 24)
                Image(systemName: event.type.icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(event.type.displayName)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    if let tab = event.tabTitle {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(tab)
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(event.timeString)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                Text(event.detail)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}
