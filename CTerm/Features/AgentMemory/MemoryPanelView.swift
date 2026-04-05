// MemoryPanelView.swift
// CTerm
//
// "What I know about this project" — browsable, deletable memory panel.
// Accessible from the sidebar in one click. Shows all stored facts with
// timestamps and delete buttons. Memory should feel like a notebook.

import SwiftUI

struct MemoryPanelView: View {
    let projectKey: String
    @State private var entries: [MemoryEntry] = []
    @State private var searchText: String = ""

    private var filteredEntries: [MemoryEntry] {
        if searchText.isEmpty { return entries }
        let q = searchText.lowercased()
        return entries.filter {
            $0.key.lowercased().contains(q) || $0.value.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(.secondary)
                Text("Project Memory")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(entries.count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1), in: Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Search
            if entries.count > 5 {
                TextField("Filter memories…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }

            Divider()

            // Entries
            if filteredEntries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 24))
                        .foregroundStyle(.quaternary)
                    Text(entries.isEmpty ? "No memories yet" : "No matches")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 40)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredEntries) { entry in
                            MemoryEntryRow(
                                entry: entry,
                                onDelete: { deleteEntry(entry) },
                                onSave: { newValue in saveEntry(entry, newValue: newValue) }
                            )
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
            }
        }
        .onAppear { refresh() }
    }

    private func refresh() {
        entries = AgentMemoryStore.shared.listAll(projectKey: projectKey)
    }

    private func deleteEntry(_ entry: MemoryEntry) {
        AgentMemoryStore.shared.forget(projectKey: projectKey, key: entry.key)
        entries.removeAll { $0.id == entry.id }
    }

    private func saveEntry(_ entry: MemoryEntry, newValue: String) {
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != entry.value else { return }
        _ = AgentMemoryStore.shared.remember(
            projectKey: projectKey,
            key: entry.key,
            value: trimmed,
            ttlDays: nil,
            category: entry.category,
            importance: entry.importance,
            confidence: entry.confidence,
            source: .userProvided
        )
        refresh()
    }
}

// MARK: - Entry Row

private struct MemoryEntryRow: View {
    let entry: MemoryEntry
    let onDelete: () -> Void
    let onSave: (String) -> Void

    @State private var isHovering = false
    @State private var isEditing = false
    @State private var draftValue: String = ""
    @FocusState private var editorFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: categoryIcon)
                .font(.system(size: 10))
                .foregroundStyle(categoryColor)
                .frame(width: 14, height: 14)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.key)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                if isEditing {
                    TextField("", text: $draftValue, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 10, design: .rounded))
                        .lineLimit(1...4)
                        .focused($editorFocused)
                        .onSubmit { commit() }
                        .onExitCommand { cancel() }
                } else {
                    Text(entry.value)
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .onTapGesture(count: 2) { beginEditing() }
                }
                HStack(spacing: 8) {
                    Text(entry.age)
                        .font(.system(size: 9, design: .rounded))
                        .foregroundStyle(.quaternary)
                    Text(entry.category.rawValue)
                        .font(.system(size: 9, design: .rounded))
                        .foregroundStyle(.quaternary)
                    if entry.source == .autoExtracted {
                        Text("auto")
                            .font(.system(size: 8, design: .rounded))
                            .foregroundStyle(.quaternary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.08), in: Capsule())
                    }
                }
            }

            Spacer()

            if isEditing {
                HStack(spacing: 4) {
                    Button(action: { cancel() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Cancel (Esc)")
                    Button(action: { commit() }) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                    .help("Save (Return)")
                }
            } else if isHovering {
                HStack(spacing: 4) {
                    Button(action: beginEditing) {
                        Image(systemName: "pencil")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Edit")
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundStyle(.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .help("Delete")
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovering ? Color.white.opacity(0.04) : Color.clear)
        )
        .onHover { isHovering = $0 }
    }

    private func beginEditing() {
        draftValue = entry.value
        isEditing = true
        // Defer focus to after the TextField mounts.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            editorFocused = true
        }
    }

    private func commit() {
        onSave(draftValue)
        isEditing = false
    }

    private func cancel() {
        draftValue = entry.value
        isEditing = false
    }

    private var categoryIcon: String {
        switch entry.category {
        case .projectFact:      return "doc.text"
        case .userPreference:   return "person"
        case .recurringCommand: return "terminal"
        case .knownBroken:      return "exclamationmark.triangle"
        case .importantPath:    return "folder"
        case .buildConfig:      return "hammer"
        case .handoff:          return "arrow.right.arrow.left"
        }
    }

    private var categoryColor: Color {
        switch entry.category {
        case .projectFact:      return .blue
        case .userPreference:   return .purple
        case .recurringCommand: return .green
        case .knownBroken:      return .red
        case .importantPath:    return .orange
        case .buildConfig:      return .teal
        case .handoff:          return .gray
        }
    }
}
