// FileChangesView.swift
// Calyx
//
// Sidebar panel listing files modified by Claude agents, grouped by peer.

import SwiftUI

struct FileChangesView: View {
    var onOpenDiff: ((DiffSource) -> Void)?
    var onOpenAggregateDiff: ((String) -> Void)?  // workDir

    @State private var store: FileChangeStore = .shared

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if store.changesByPeer.isEmpty {
                    emptyState
                } else {
                    headerActions
                    peerSections
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            VStack(spacing: 4) {
                Text("No changes tracked yet")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("Claude agents can call\nreport_file_change to track edits here.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: - Header Actions

    private var headerActions: some View {
        HStack(spacing: 8) {
            Button(action: openAggregateDiff) {
                Label("All Changes", systemImage: "doc.text.magnifyingglass")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(aggregateWorkDir == nil)
            .help(aggregateWorkDir == nil
                ? "All Changes is only available when tracked files belong to a single repository."
                : "Open aggregate diff for all tracked files")

            Spacer()

            Button("Clear") {
                store.clearAll()
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, design: .rounded))
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Peer Sections

    private var peerSections: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(sortedPeerIDs, id: \.self) { peerID in
                if let changes = store.changesByPeer[peerID], !changes.isEmpty {
                    PeerFileSection(
                        peerName: changes[0].peerName,
                        changes: changes.sorted { $0.timestamp > $1.timestamp },
                        onOpenDiff: openDiffForChange
                    )
                }
            }
        }
    }

    // MARK: - Helpers

    private var sortedPeerIDs: [UUID] {
        store.changesByPeer.keys.sorted { a, b in
            let aLast = store.changesByPeer[a]?.last?.timestamp ?? .distantPast
            let bLast = store.changesByPeer[b]?.last?.timestamp ?? .distantPast
            return aLast > bLast
        }
    }

    private func openDiffForChange(_ change: TrackedFileChange) {
        onOpenDiff?(.unstaged(path: change.path, workDir: change.workDir))
    }

    private func openAggregateDiff() {
        guard let aggregateWorkDir else { return }
        onOpenAggregateDiff?(aggregateWorkDir)
    }

    private var aggregateWorkDir: String? {
        let workDirs = store.trackedWorkDirs
        guard workDirs.count == 1 else { return nil }
        return workDirs[0]
    }
}

// MARK: - PeerFileSection

private struct PeerFileSection: View {
    let peerName: String
    let changes: [TrackedFileChange]
    var onOpenDiff: (TrackedFileChange) -> Void

    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Section header
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } }) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(isExpanded ? .degrees(90) : .zero)
                    Label(peerName, systemImage: "person.fill")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .tracking(0.4)
                    Spacer()
                    Text("\(changes.count)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 2) {
                    ForEach(changes) { change in
                        FileChangeRow(change: change, onTap: { onOpenDiff(change) })
                    }
                }
            }
        }
    }
}

// MARK: - FileChangeRow

private struct FileChangeRow: View {
    let change: TrackedFileChange
    var onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text(change.fileName)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .lineLimit(1)
                    Text(change.relativePath)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Image(systemName: "arrow.right.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .opacity(isHovering ? 1 : 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isHovering ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
