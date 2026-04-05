// AgentSessionHistoryView.swift
// CTerm
//
// Sidebar view surfacing AgentSessionRegistry.history. Turns the in-memory
// registry into a scrollable, reviewable artifact: each row shows the
// session's intent, final phase, duration, and a brief summary preview.

import SwiftUI

@MainActor
struct AgentSessionHistoryView: View {
    private let registry = AgentSessionRegistry.shared
    @State private var searchQuery: String = ""

    private var filteredHistory: [AgentSession] {
        let h = registry.history
        guard !searchQuery.isEmpty else { return h }
        let q = searchQuery.lowercased()
        return h.filter {
            $0.displayIntent.lowercased().contains(q)
                || ($0.result?.summary.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if registry.history.count > 5 {
                searchField
            }
            Divider().padding(.vertical, 6)
            if filteredHistory.isEmpty {
                emptyState
            } else {
                historyList
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Agent History")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Text("\(registry.history.count)")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 8)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("Search past sessions", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
            if !searchQuery.isEmpty {
                Button(action: { searchQuery = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text(registry.history.isEmpty
                 ? "No past sessions yet"
                 : "No matches")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 40)
    }

    // MARK: - List

    private var historyList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(filteredHistory, id: \.id) { session in
                    sessionRow(session)
                }
            }
            .padding(.bottom, 8)
        }
        .scrollIndicators(.never)
    }

    @ViewBuilder
    private func sessionRow(_ session: AgentSession) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: phaseIcon(session.phase))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(phaseColor(session.phase))
                    .frame(width: 14)

                Text(truncate(session.displayIntent, to: 80))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Spacer(minLength: 4)
            }

            if let summary = session.result?.summary, !summary.isEmpty {
                Text(summary)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .padding(.leading, 20)
            }

            HStack(spacing: 6) {
                Text(kindLabel(session.kind))
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                Text("·")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Text(relativeTime(session.startedAt))
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.tertiary)
                if let dur = durationText(session) {
                    Text("·")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Text(dur)
                        .font(.system(size: 9, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .padding(.leading, 20)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
    }

    // MARK: - Helpers

    private func phaseIcon(_ phase: AgentPhase) -> String {
        switch phase {
        case .completed: return "checkmark.circle.fill"
        case .failed:    return "xmark.octagon.fill"
        case .cancelled: return "stop.circle.fill"
        default:         return "circle.dotted"
        }
    }

    private func phaseColor(_ phase: AgentPhase) -> Color {
        switch phase {
        case .completed: return .green
        case .failed:    return .red
        case .cancelled: return .orange
        default:         return .secondary
        }
    }

    private func kindLabel(_ kind: AgentSessionKind) -> String {
        switch kind {
        case .inline:    return "inline"
        case .multiStep: return "multi-step"
        case .queued:    return "queued"
        case .delegated: return "delegated"
        }
    }

    private func durationText(_ session: AgentSession) -> String? {
        if let ms = session.result?.durationMs {
            let seconds = Double(ms) / 1000
            if seconds < 1 { return "\(ms)ms" }
            return String(format: "%.1fs", seconds)
        }
        return nil
    }

    private func relativeTime(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }

    private func truncate(_ s: String, to length: Int) -> String {
        if s.count <= length { return s }
        return String(s.prefix(length)) + "…"
    }
}
