// InlineDiffView.swift
// CTerm
//
// Compact per-file diff row embedded in the agent run panel's summary
// block. Collapsed by default: shows status glyph, path and +N −M chip.
// When expanded, lazily loads `git diff HEAD -- <path>` (or a synthesized
// diff for untracked files), parses it with DiffParser, and renders a
// lightweight SwiftUI hunk view inline. Each hunk gets its own revert
// button; a file-level "Revert file" button sits in the footer. Every
// revert is routed through ApprovalPresenter's standalone-approval path.

import SwiftUI
import OSLog

private let logger = Logger(subsystem: "com.legato3.cterm", category: "InlineDiffView")

struct InlineDiffView: View {
    let file: ChangedFile
    let workingDir: String
    /// Called after a successful revert so the parent can drop this row
    /// from `session.result.filesChanged`.
    var onReverted: (() -> Void)? = nil

    @State private var isExpanded: Bool = false
    @State private var loadState: LoadState = .idle
    @State private var isReverting: Bool = false
    @State private var revertError: String? = nil
    @State private var hunkRevertingIndex: Int? = nil
    @State private var hunkRevertErrors: [Int: String] = [:]

    private enum LoadState {
        case idle
        case loading
        case loaded(FileDiff)
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                expandedBody
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    // MARK: - Header (always visible)

    private var header: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) {
                isExpanded.toggle()
            }
            if isExpanded, case .idle = loadState {
                Task { await loadDiff() }
            }
        } label: {
            HStack(spacing: 6) {
                statusGlyph
                Text(file.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                statChip
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var statusGlyph: some View {
        Text(statusSymbol)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(statusColor)
            .frame(width: 12, alignment: .center)
    }

    private var statusSymbol: String {
        switch file.status {
        case .added:     return "+"
        case .modified:  return "~"
        case .deleted:   return "−"
        case .renamed:   return "→"
        case .untracked: return "•"
        }
    }

    private var statusColor: Color {
        switch file.status {
        case .added:     return .green
        case .modified:  return .yellow
        case .deleted:   return .red
        case .renamed:   return .blue
        case .untracked: return .secondary
        }
    }

    @ViewBuilder
    private var statChip: some View {
        if file.additions > 0 || file.deletions > 0 {
            HStack(spacing: 4) {
                if file.additions > 0 {
                    Text("+\(file.additions)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.green)
                }
                if file.deletions > 0 {
                    Text("−\(file.deletions)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.red)
                }
            }
        }
    }

    // MARK: - Expanded body

    @ViewBuilder
    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().background(Color.white.opacity(0.06))
            diffContent
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            Divider().background(Color.white.opacity(0.06))
            footer
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private var diffContent: some View {
        switch loadState {
        case .idle, .loading:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Loading diff…")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .failed(let message):
            Text(message)
                .font(.system(size: 10))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .loaded(let diff):
            if diff.isBinary {
                Text("Binary file — diff not shown")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            } else if diff.lines.isEmpty {
                Text("No changes")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else if diff.hunks.isEmpty {
                // Untracked / synthetic diff with no hunk structure — fall
                // back to flat line rendering.
                diffLines(diff)
            } else {
                hunkList(diff)
            }
        }
    }

    private func diffLines(_ diff: FileDiff) -> some View {
        // Filter out meta lines — callers only need hunk headers +
        // context/add/delete rows. Cap at 200 visible lines to keep the
        // run panel responsive inside a parent ScrollView.
        let visible = diff.lines
            .filter { $0.type != .meta }
            .prefix(200)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(visible.enumerated()), id: \.offset) { _, line in
                lineRow(line)
            }
            if diff.lines.count > 200 || diff.isTruncated {
                Text("… diff truncated")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
    }

    private func hunkList(_ diff: FileDiff) -> some View {
        var remaining = 200
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(diff.hunks.enumerated()), id: \.offset) { idx, hunk in
                let available = max(0, remaining)
                let shown = min(hunk.bodyLines.count, available)
                let _ = (remaining -= shown)
                hunkBlock(
                    hunk: hunk,
                    index: idx,
                    truncatedBody: shown < hunk.bodyLines.count
                        ? Array(hunk.bodyLines.prefix(shown))
                        : hunk.bodyLines
                )
            }
            if diff.isTruncated || remaining <= 0 {
                Text("… diff truncated")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
    }

    @ViewBuilder
    private func hunkBlock(hunk: DiffHunk, index: Int, truncatedBody: [String]) -> some View {
        let isBusy = hunkRevertingIndex == index
        let err = hunkRevertErrors[index]
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text(hunk.header)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    Task { await performHunkRevert(index: index, hunk: hunk) }
                } label: {
                    if isBusy {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 9, weight: .semibold))
                    }
                }
                .buttonStyle(.plain)
                .help("Revert this hunk")
                .foregroundStyle(.secondary)
                .disabled(isBusy || isReverting)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.08))

            ForEach(Array(truncatedBody.enumerated()), id: \.offset) { _, raw in
                bodyLineRow(raw)
            }

            if let err {
                Text(err)
                    .font(.system(size: 9))
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
            }
        }
    }

    private func bodyLineRow(_ raw: String) -> some View {
        let first = raw.first
        let (color, bg): (Color, Color) = {
            switch first {
            case "+": return (.green, Color.green.opacity(0.08))
            case "-": return (.red,   Color.red.opacity(0.08))
            case "\\": return (.secondary, Color.clear)
            default:  return (.primary, Color.clear)
            }
        }()
        return Text(raw)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.vertical, 0.5)
            .background(bg)
    }

    private func lineRow(_ line: DiffLine) -> some View {
        let (prefix, color, bg): (String, Color, Color) = {
            switch line.type {
            case .addition:   return ("+", .green,      Color.green.opacity(0.08))
            case .deletion:   return ("−", .red,        Color.red.opacity(0.08))
            case .hunkHeader: return (" ", .accentColor, Color.accentColor.opacity(0.08))
            case .context:    return (" ", .secondary,   Color.clear)
            case .meta:       return (" ", .secondary,   Color.clear)
            }
        }()
        return HStack(alignment: .top, spacing: 4) {
            Text(prefix)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(color)
                .frame(width: 10, alignment: .leading)
            Text(line.text)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(line.type == .hunkHeader ? color : .primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 0.5)
        .background(bg)
    }

    // MARK: - Footer (revert)

    private var footer: some View {
        HStack(spacing: 8) {
            if let revertError {
                Text(revertError)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
            Button {
                Task { await performRevert() }
            } label: {
                if isReverting {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.mini)
                        Text("Reverting…").font(.system(size: 10, weight: .medium))
                    }
                } else {
                    Label("Revert file", systemImage: "arrow.uturn.backward")
                        .font(.system(size: 10, weight: .medium))
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .tint(.red)
            .disabled(isReverting)
        }
    }

    // MARK: - Diff loading

    private func loadDiff() async {
        loadState = .loading
        do {
            let source: DiffSource = file.status == .untracked
                ? .untracked(path: file.path, workDir: workingDir)
                : .unstaged(path: file.path, workDir: workingDir)
            let raw = try await GitService.fileDiff(source: source)
            let parsed = DiffParser.parse(raw, path: file.path)
            loadState = .loaded(parsed)
        } catch {
            logger.error("InlineDiffView: failed to load diff for \(file.path): \(error.localizedDescription)")
            loadState = .failed("Could not load diff: \(error.localizedDescription)")
        }
    }

    // MARK: - Revert (gated via ApprovalPresenter)

    private func performRevert() async {
        guard !isReverting, hunkRevertingIndex == nil else { return }
        revertError = nil

        let commandPreview = revertCommandPreview()
        let descriptor = ActionDescriptor(
            what: "Revert file `\(file.path)`",
            why: "User requested revert of agent-authored change",
            impact: "Discards all working-tree changes to this file. Cannot be undone.",
            rollback: "`git reflog` may help recover if needed"
        )

        let answer = await requestApproval(command: commandPreview, descriptor: descriptor)
        guard answer == .approved else {
            if answer == .denied { revertError = "Revert declined" }
            return
        }

        isReverting = true
        defer { isReverting = false }
        do {
            try await GitService.revertFile(path: file.path, status: file.status, workDir: workingDir)
            onReverted?()
        } catch {
            logger.error("InlineDiffView: revert failed for \(file.path): \(error.localizedDescription)")
            revertError = "Revert failed: \(error.localizedDescription)"
        }
    }

    private func performHunkRevert(index: Int, hunk: DiffHunk) async {
        guard !isReverting, hunkRevertingIndex == nil else { return }
        hunkRevertErrors[index] = nil

        let lineRange = "lines \(hunk.newStart)-\(hunk.newStart + max(0, hunk.newCount - 1))"
        let descriptor = ActionDescriptor(
            what: "Revert hunk in `\(file.path)` (\(lineRange))",
            why: "User requested revert of agent-authored change",
            impact: "Discards this hunk. Cannot be undone.",
            rollback: "`git reflog` may help recover if needed"
        )
        // Frame as a git-apply command so HardStopGuard and RiskScorer can
        // reason about it consistently with file-level reverts.
        let commandPreview = "git apply -R -- <hunk patch for \(file.path)>"

        let answer = await requestApproval(command: commandPreview, descriptor: descriptor)
        guard answer == .approved else {
            if answer == .denied { hunkRevertErrors[index] = "Declined" }
            return
        }

        hunkRevertingIndex = index
        defer { hunkRevertingIndex = nil }
        do {
            try await GitService.revertHunk(filePath: file.path, hunk: hunk, workDir: workingDir)
            // Reload the diff to reflect the remaining hunks.
            await loadDiff()
            if case .loaded(let updated) = loadState, updated.hunks.isEmpty, updated.lines.isEmpty {
                onReverted?()
            } else if case .loaded(let updated) = loadState, updated.hunks.isEmpty {
                // No remaining hunks after revert — drop the file row.
                onReverted?()
            }
        } catch {
            logger.error("InlineDiffView: hunk revert failed for \(file.path): \(error.localizedDescription)")
            hunkRevertErrors[index] = "Apply failed: \(error.localizedDescription)"
        }
    }

    private func requestApproval(command: String, descriptor: ActionDescriptor) async -> ApprovalAnswer {
        await withCheckedContinuation { continuation in
            ApprovalPresenter.shared.requestStandaloneApproval(
                command: command,
                descriptor: descriptor,
                repoPath: workingDir,
                gitBranch: nil,
                onResolve: { answer in
                    continuation.resume(returning: answer)
                }
            )
        }
    }

    private func revertCommandPreview() -> String {
        switch file.status {
        case .modified, .deleted, .renamed:
            return "git checkout -- \(file.path)"
        case .added:
            return "git rm -f -- \(file.path)"
        case .untracked:
            return "git clean -f -- \(file.path)"
        }
    }
}

#Preview {
    VStack(spacing: 4) {
        InlineDiffView(
            file: ChangedFile(path: "CTerm/Views/Agent/AgentRunPanelView.swift", status: .modified, additions: 12, deletions: 4),
            workingDir: "/tmp"
        )
        InlineDiffView(
            file: ChangedFile(path: "newfile.swift", status: .untracked, additions: 30, deletions: 0),
            workingDir: "/tmp"
        )
    }
    .padding()
    .frame(width: 420)
}
