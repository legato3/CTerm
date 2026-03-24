// TerminalSearchOverlay.swift
// Calyx
//
// Floating search panel triggered by Cmd+Shift+F.
// Full-text searches across all indexed terminal output via TerminalSearchIndex.

import SwiftUI

// MARK: - TerminalSearchOverlay

struct TerminalSearchOverlay: View {
    let onDismiss: () -> Void
    /// Called when the user clicks a result — jump to the tab whose ID is `paneID`.
    let onJumpToPane: (String) -> Void

    @State private var query: String = ""
    @State private var results: [TerminalSearchResult] = []
    @State private var isSearching: Bool = false
    @FocusState private var searchFocused: Bool
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            resultsList
        }
        .frame(width: 560, height: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
        .onAppear {
            searchFocused = true
            TerminalSearchIndex.shared.pruneOldEntries()
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

            TextField("Search terminal output…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($searchFocused)
                .onChange(of: query) { _, newValue in
                    scheduleSearch(query: newValue)
                }
                .onKeyPress(.return) {
                    if let first = results.first {
                        onJumpToPane(first.paneID)
                        onDismiss()
                    }
                    return .handled
                }

            if isSearching {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 16, height: 16)
            } else if !query.isEmpty {
                Button {
                    query = ""
                    results = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsList: some View {
        if results.isEmpty && !query.isEmpty && !isSearching {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 28))
                    .foregroundStyle(.quaternary)
                Text("No results for \"\(query)\"")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        } else if results.isEmpty && query.isEmpty {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "terminal")
                    .font(.system(size: 28))
                    .foregroundStyle(.quaternary)
                Text("Search across all terminal output")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Text("Supports FTS5 phrases: \"exact phrase\", word:prefix")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(results) { result in
                        ResultRow(result: result, query: query) {
                            onJumpToPane(result.paneID)
                            onDismiss()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Search Logic

    private func scheduleSearch(query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)  // 250ms debounce
            guard !Task.isCancelled else { return }
            let found = TerminalSearchIndex.shared.search(query: trimmed)
            await MainActor.run {
                self.results = found
                self.isSearching = false
            }
        }
    }
}

// MARK: - ResultRow

private struct ResultRow: View {
    let result: TerminalSearchResult
    let query: String
    let action: () -> Void

    @State private var isHovered: Bool = false

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                // Pane badge
                Text(result.paneTitle.prefix(12))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 80, alignment: .leading)

                // Line content with highlight
                highlightedLine
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.primary)

                // Timestamp
                Text(Self.timeFormatter.string(from: result.timestamp))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(width: 56, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isHovered ? Color.primary.opacity(0.06) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var highlightedLine: Text {
        let line = result.line
        let lower = line.lowercased()
        let queryLower = query.trimmingCharacters(in: .init(charactersIn: "\"")).lowercased()

        guard !queryLower.isEmpty, let range = lower.range(of: queryLower) else {
            return Text(line)
        }

        // Split into before/match/after and apply bold to match
        let before = String(line[line.startIndex..<range.lowerBound])
        let match  = String(line[range])
        let after  = String(line[range.upperBound...])

        return Text(before) + Text(match).bold().foregroundStyle(Color.accentColor) + Text(after)
    }
}

// MARK: - Container (overlay entry point)

/// Wraps TerminalSearchOverlay with a dim background for tap-to-dismiss.
struct TerminalSearchContainer: View {
    let onDismiss: () -> Void
    let onJumpToPane: (String) -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.01)
                .onTapGesture { onDismiss() }

            VStack {
                TerminalSearchOverlay(onDismiss: onDismiss, onJumpToPane: onJumpToPane)
                    .padding(.top, 40)
                Spacer()
            }
        }
    }
}
