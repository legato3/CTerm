// AgentMemoryView.swift
// Calyx
//
// Sidebar panel for browsing, searching, and managing agent memories.

import SwiftUI

struct AgentMemoryView: View {
    @State private var entries: [MemoryEntry] = []
    @State private var searchText = ""
    @State private var projectKey = ""
    @State private var showingAddSheet = false

    private var filtered: [MemoryEntry] {
        let q = searchText.lowercased()
        guard !q.isEmpty else { return entries }
        return entries.filter {
            $0.key.lowercased().contains(q) || $0.value.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchBar
            Divider().opacity(0.4)

            if filtered.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(filtered) { entry in
                            MemoryRowView(entry: entry) {
                                delete(entry)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
            }
        }
        .task { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .agentMemoryChanged)) { _ in
            Task { await reload() }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddMemorySheet(projectKey: projectKey) {
                Task { await reload() }
            }
        }
    }

    // MARK: - Sub-views

    private var header: some View {
        HStack(spacing: 6) {
            Label("Memories", systemImage: "brain.head.profile")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .tracking(0.5)
            Spacer()
            if !entries.isEmpty {
                Text("\(entries.count)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            Button(action: { showingAddSheet = true }) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Add a memory")
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            TextField("Search memories…", text: $searchText)
                .font(.system(size: 12, design: .rounded))
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "brain.head.profile")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            if searchText.isEmpty {
                Text("No memories yet")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("Agents can store project facts with\nthe **remember** MCP tool.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            } else {
                Text("No matches for \"\(searchText)\"")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - Actions

    private func reload() async {
        let pwd = await MainActor.run {
            TerminalControlBridge.shared.delegate?.activeTabPwd ?? FileManager.default.currentDirectoryPath
        }
        projectKey = AgentMemoryStore.key(for: pwd)
        let loaded = AgentMemoryStore.shared.listAll(projectKey: projectKey)
        await MainActor.run { entries = loaded }
    }

    private func delete(_ entry: MemoryEntry) {
        AgentMemoryStore.shared.forget(projectKey: projectKey, key: entry.key)
        entries.removeAll { $0.id == entry.id }
        NotificationCenter.default.post(name: .agentMemoryChanged, object: nil)
    }
}

// MARK: - Row

private struct MemoryRowView: View {
    let entry: MemoryEntry
    var onDelete: (() -> Void)?
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.key)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(entry.value)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text(entry.age)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    if let exp = entry.expiresAt {
                        Text("· expires \(exp.formatted(.relative(presentation: .named)))")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer()
            Button(action: { onDelete?() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .opacity(isHovering ? 1 : 0)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Forget this memory")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(isHovering ? 0.08 : 0.04))
        )
        .onAssumeInsideHover($isHovering)
        .contextMenu {
            Button("Forget") { onDelete?() }
            Button("Copy Key") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(entry.key, forType: .string) }
            Button("Copy Value") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(entry.value, forType: .string) }
        }
    }
}

// MARK: - Add Sheet

private struct AddMemorySheet: View {
    let projectKey: String
    var onSaved: (() -> Void)?

    @State private var key = ""
    @State private var value = ""
    @State private var ttlEnabled = false
    @State private var ttlDays = 7
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Memory")
                .font(.system(size: 16, weight: .semibold, design: .rounded))

            VStack(alignment: .leading, spacing: 6) {
                Text("Key").font(.caption).foregroundStyle(.secondary)
                TextField("e.g. auth-system", text: $key)
                    .textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Value").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $value)
                    .font(.system(size: 12, design: .rounded))
                    .frame(minHeight: 80, maxHeight: 200)
                    .border(Color.secondary.opacity(0.3), width: 0.5)
                    .cornerRadius(4)
            }
            Toggle("Expires after \(ttlDays) days", isOn: $ttlEnabled)
            if ttlEnabled {
                Stepper("", value: $ttlDays, in: 1...365).labelsHidden()
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedKey.isEmpty, !trimmedValue.isEmpty else { return }
                    AgentMemoryStore.shared.remember(
                        projectKey: projectKey,
                        key: trimmedKey,
                        value: trimmedValue,
                        ttlDays: ttlEnabled ? ttlDays : nil
                    )
                    NotificationCenter.default.post(name: .agentMemoryChanged, object: nil)
                    onSaved?()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
