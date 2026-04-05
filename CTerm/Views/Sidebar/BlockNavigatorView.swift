// BlockNavigatorView.swift
// CTerm
//
// Block Navigator sidebar. Lists every captured terminal command block across
// all tabs in the current window with full-text search, scope toggle
// (all tabs / this tab), and a status filter (all / succeeded / failed /
// running). Blocks can be attached to the currently active tab with one click.

import SwiftUI

private let kBlockNavigatorMaxRows = 500

@MainActor
struct BlockNavigatorView: View {
    let windowSession: WindowSession
    let currentTab: Tab?

    @State private var searchQuery: String = ""
    @State private var scope: BlockNavigatorScope = .allTabs
    @State private var statusFilter: BlockStatusFilter = .all
    @State private var selectedBlockID: UUID?
    @State private var recentlyAttached: Set<UUID> = []
    @State private var hoveredBlockID: UUID?
    @State private var recentlyCopied: Set<UUID> = []

    private var allBlocks: [BlockWithTab] {
        var out: [BlockWithTab] = []
        for group in windowSession.groups {
            for tab in group.tabs {
                let title = tab.titleOverride ?? tab.title
                for block in tab.blockStore.all {
                    out.append(BlockWithTab(block: block, tabID: tab.id, tabTitle: title))
                }
            }
        }
        // Newest-first across the window: blockStore already maintains newest-first per tab,
        // so interleave by startedAt descending.
        out.sort { $0.block.startedAt > $1.block.startedAt }
        return out
    }

    private var filtered: [BlockWithTab] {
        BlockNavigatorFilter.apply(
            blocks: allBlocks,
            scope: scope,
            currentTabID: currentTab?.id,
            status: statusFilter,
            searchQuery: searchQuery
        )
    }

    private var totalCount: Int { filtered.count }
    private var displayedRows: [BlockWithTab] { Array(filtered.prefix(kBlockNavigatorMaxRows)) }
    private var isTruncated: Bool { filtered.count > kBlockNavigatorMaxRows }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            searchField
            filterChips
            Divider()
                .padding(.vertical, 6)
            if totalCount == 0 {
                emptyState
            } else {
                blockList
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Blocks")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Text("\(totalCount) block\(totalCount == 1 ? "" : "s")")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 8)
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("Search commands & output", text: $searchQuery)
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
        .padding(.bottom, 8)
    }

    // MARK: - Filter Chips

    private var filterChips: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                scopeChip(.allTabs, label: "All tabs")
                scopeChip(.currentTab, label: "This tab")
                Spacer()
            }
            HStack(spacing: 4) {
                ForEach(BlockStatusFilter.allCases) { filter in
                    statusChip(filter)
                }
                Spacer()
            }
        }
    }

    private func scopeChip(_ value: BlockNavigatorScope, label: String) -> some View {
        let isSelected = scope == value
        return Button(action: { scope = value }) {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(isSelected ? Color.accentColor.opacity(0.25) : Color.white.opacity(0.06))
                )
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
    }

    private func statusChip(_ value: BlockStatusFilter) -> some View {
        let isSelected = statusFilter == value
        return Button(action: { statusFilter = value }) {
            Text(value.label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(isSelected ? Color.accentColor.opacity(0.25) : Color.white.opacity(0.06))
                )
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text(searchQuery.isEmpty && statusFilter == .all
                 ? "No blocks captured yet"
                 : "No matches")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 40)
    }

    // MARK: - Block List

    private var blockList: some View {
        ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                if scope == .allTabs {
                    let grouped = Dictionary(grouping: displayedRows, by: { $0.tabID })
                    // Preserve ordering by the earliest (most recent) block per tab in displayedRows.
                    let tabOrder: [UUID] = {
                        var seen = Set<UUID>()
                        var order: [UUID] = []
                        for row in displayedRows {
                            if !seen.contains(row.tabID) {
                                seen.insert(row.tabID)
                                order.append(row.tabID)
                            }
                        }
                        return order
                    }()
                    ForEach(tabOrder, id: \.self) { tabID in
                        if let rows = grouped[tabID], let first = rows.first {
                            Section(header: sectionHeader(title: first.tabTitle, count: rows.count)) {
                                ForEach(rows) { row in
                                    blockRow(row)
                                }
                            }
                        }
                    }
                } else {
                    ForEach(displayedRows) { row in
                        blockRow(row)
                    }
                }

                if isTruncated {
                    Text("Showing first \(kBlockNavigatorMaxRows) of \(totalCount) · refine search")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
            }
            .padding(.bottom, 8)
        }
        .scrollIndicators(.never)
        .focusable()
        .onKeyPress(keys: [.upArrow, .downArrow]) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            let delta = press.key == .downArrow ? 1 : -1
            if let newID = moveSelection(by: delta) {
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(newID, anchor: .center)
                }
            }
            return .handled
        }
        } // ScrollViewReader
    }

    private func sectionHeader(title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "terminal")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text(title.isEmpty ? "Terminal" : title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.system(size: 9, design: .rounded))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.12))
    }

    // MARK: - Row

    @ViewBuilder
    private func blockRow(_ row: BlockWithTab) -> some View {
        let isSelected = selectedBlockID == row.block.id
        let isAttached = currentTab?.attachedBlockIDs.contains(row.block.id) ?? false
        let justAttached = recentlyAttached.contains(row.block.id)

        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(statusGlyph(for: row.block))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(statusColor(for: row.block))
                    .frame(width: 12)

                Text(truncate(row.block.titleText, to: 60))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if hoveredBlockID == row.block.id {
                    hoverActions(for: row)
                        .transition(.opacity)
                }
                attachButton(for: row, isAttached: isAttached, justAttached: justAttached)
            }

            HStack(spacing: 4) {
                Text(row.tabTitle.isEmpty ? "Terminal" : row.tabTitle)
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.tertiary)
                Text("·")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Text(relativeTime(for: row.block.startedAt))
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.tertiary)
                if let cwd = row.block.cwd, let basename = cwdBasename(cwd) {
                    Text("·")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Text(basename)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                if let exitCode = row.block.exitCode {
                    Text("·")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Text("exit \(exitCode)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(exitCode == 0 ? Color.green.opacity(0.8) : Color.red.opacity(0.8))
                }
                if let dur = row.block.durationText {
                    Text("·")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Text(dur)
                        .font(.system(size: 9, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .padding(.leading, 18)

            if isSelected, let snippet = row.block.primarySnippet {
                Text(snippet)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(8)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.black.opacity(0.18))
                    )
                    .padding(.leading, 18)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedBlockID = (selectedBlockID == row.block.id) ? nil : row.block.id
        }
        .onHover { inside in
            hoveredBlockID = inside ? row.block.id : (hoveredBlockID == row.block.id ? nil : hoveredBlockID)
        }
        .id(row.block.id)
    }

    // MARK: - Hover Actions

    @ViewBuilder
    private func hoverActions(for row: BlockWithTab) -> some View {
        let justCopied = recentlyCopied.contains(row.block.id)
        HStack(spacing: 2) {
            hoverButton(
                symbol: justCopied ? "checkmark" : "doc.on.doc",
                tint: justCopied ? .green : .secondary,
                help: "Copy command"
            ) {
                copyToPasteboard(row.block.titleText, markID: row.block.id)
            }
            .disabled(row.block.command == nil)

            hoverButton(
                symbol: "text.alignleft",
                tint: .secondary,
                help: "Copy output"
            ) {
                if let snippet = row.block.primarySnippet {
                    copyToPasteboard(snippet, markID: row.block.id)
                }
            }
            .disabled(row.block.primarySnippet == nil)

            hoverButton(
                symbol: "arrow.clockwise",
                tint: .accentColor,
                help: "Rerun in current tab"
            ) {
                rerunInCurrentTab(row)
            }
            .disabled(currentTab == nil || row.block.command == nil)
        }
    }

    private func hoverButton(
        symbol: String,
        tint: Color,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func copyToPasteboard(_ text: String, markID: UUID) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        recentlyCopied.insert(markID)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            recentlyCopied.remove(markID)
        }
    }

    private func rerunInCurrentTab(_ row: BlockWithTab) {
        guard let tab = currentTab, let command = row.block.command else { return }
        _ = TerminalControlBridge.shared.delegate?.runInPane(
            tabID: tab.id,
            paneID: nil,
            text: command,
            pressEnter: true
        )
    }

    private func attachButton(
        for row: BlockWithTab,
        isAttached: Bool,
        justAttached: Bool
    ) -> some View {
        let symbol: String
        let color: Color
        if justAttached {
            symbol = "checkmark"
            color = .green
        } else if isAttached {
            symbol = "minus.circle.fill"
            color = .orange
        } else {
            symbol = "plus.circle"
            color = .accentColor
        }

        return Button(action: { toggleAttach(row) }) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(currentTab == nil)
        .help(isAttached ? "Detach from current tab" : "Attach to current tab")
    }

    // MARK: - Actions

    /// Move `selectedBlockID` by `delta` within `displayedRows` (wraps).
    /// Returns the new selected ID (for scroll-to), or nil if no rows.
    private func moveSelection(by delta: Int) -> UUID? {
        guard !displayedRows.isEmpty else { return nil }
        let ids = displayedRows.map { $0.block.id }
        if let current = selectedBlockID, let idx = ids.firstIndex(of: current) {
            let next = (idx + delta + ids.count) % ids.count
            selectedBlockID = ids[next]
        } else {
            selectedBlockID = delta >= 0 ? ids.first : ids.last
        }
        return selectedBlockID
    }

    private func toggleAttach(_ row: BlockWithTab) {
        guard let tab = currentTab else { return }
        let id = row.block.id
        if tab.attachedBlockIDs.contains(id) {
            tab.detachBlock(id)
        } else {
            tab.attachBlock(id)
            recentlyAttached.insert(id)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                recentlyAttached.remove(id)
            }
        }
    }

    // MARK: - Formatters

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

    private func relativeTime(for date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }

    private func cwdBasename(_ cwd: String) -> String? {
        let trimmed = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let url = URL(fileURLWithPath: trimmed)
        let name = url.lastPathComponent
        return name.isEmpty ? nil : name
    }
}
