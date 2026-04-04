// TaskQueueView.swift
// Calyx
//
// Phase 10: Task Queue sidebar panel — list queued prompts, drag to reorder,
// add/remove tasks, start/stop auto-processing.

import SwiftUI

struct TaskQueueView: View {
    @State private var store: TaskQueueStore = .shared
    @State private var agentState: IPCAgentState = .shared
    @State private var newTaskText: String = ""
    @State private var newTaskModel: TaskModel = .auto
    @State private var showingAddField: Bool = false
    @FocusState private var addFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.tasks.isEmpty {
                emptyState
            } else {
                taskList
            }
            addTaskRow
        }
        .onAppear { store.engine.startMonitoring() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "checklist")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Task Queue")
                .font(.system(size: 12, weight: .semibold, design: .rounded))

            Spacer()

            // Status badge
            if store.pendingCount > 0 {
                Text("\(store.pendingCount)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.accentColor)
                .clipShape(Capsule())
            }

            // Start / pause toggle
            Button {
                store.isProcessing.toggle()
                if store.isProcessing { store.engine.kickIfNeeded() }
            } label: {
                Image(systemName: store.isProcessing ? "pause.fill" : "play.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(store.isProcessing ? Color.orange : Color.green)
            }
            .buttonStyle(.plain)
            .help(store.isProcessing ? "Pause queue" : "Start processing queue")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("No tasks queued")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text("Add tasks below — they'll be sent\nto your selected AI agent pane in order.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 16)
    }

    // MARK: - Task List

    private var taskList: some View {
        List {
            ForEach(Array(store.tasks.enumerated()), id: \.element.id) { idx, task in
                TaskRowView(task: task, index: idx, store: store)
                    .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                    .listRowBackground(rowBackground(for: task))
                    .listRowSeparator(.hidden)
            }
            .onMove { store.moveTask(fromOffsets: $0, toOffset: $1) }
            .onDelete { store.remove(at: $0) }
        }
        .listStyle(.plain)
        .frame(minHeight: 60, maxHeight: 300)
    }

    private func rowBackground(for task: QueuedTask) -> some View {
        Group {
            if task.status == .running {
                Color.accentColor.opacity(0.08)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Color.clear
            }
        }
    }

    // MARK: - Target Peer Picker + Add Row

    private var addTaskRow: some View {
        VStack(spacing: 0) {
            Divider()
            // Target peer + default model pickers
            HStack(spacing: 6) {
                Text("Target:")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Picker("", selection: $store.defaultTargetPeerName) {
                    Text("Active pane").tag("")
                    ForEach(peerNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .labelsHidden()
                .font(.system(size: 10))
                .frame(maxWidth: .infinity)

                Text("Model:")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Picker("", selection: $store.defaultModel) {
                    ForEach(TaskModel.allCases) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                .labelsHidden()
                .font(.system(size: 10))
                .frame(width: 72)
                .help("Default model for new tasks")
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            if showingAddField {
                addField
            } else {
                addButton
            }
        }
    }

    private var addButton: some View {
        Button {
            showingAddField = true
            addFieldFocused = true
        } label: {
            Label("Add Task", systemImage: "plus.circle")
                .font(.system(size: 11))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
    }

    private var addField: some View {
        VStack(spacing: 4) {
            TextEditor(text: $newTaskText)
                .font(.system(size: 11, design: .monospaced))
                .frame(minHeight: 56, maxHeight: 120)
                .padding(6)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                .focused($addFieldFocused)
                .overlay(alignment: .topLeading) {
                    if newTaskText.isEmpty {
                        Text("Enter task prompt…")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .padding(10)
                            .allowsHitTesting(false)
                    }
                }

            HStack {
                // Model picker for this task
                Picker("", selection: $newTaskModel) {
                    ForEach(TaskModel.allCases) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .font(.system(size: 10))
                .frame(width: 72)
                .help("Model to use for this task")

                Spacer()

                Button("Cancel") {
                    newTaskText = ""
                    newTaskModel = .auto
                    showingAddField = false
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

                Spacer()

                Button("Add") { submitNewTask() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .disabled(newTaskText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }

    // MARK: - Helpers

    private var peerNames: [String] {
        agentState.peers
            .filter { $0.name != "calyx-app" }
            .map(\.name)
    }

    private func submitNewTask() {
        let trimmed = newTaskText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.enqueue(trimmed, model: newTaskModel)
        newTaskText = ""
        newTaskModel = .auto
        showingAddField = false
    }
}

// MARK: - TaskRowView

private struct TaskRowView: View {
    let task: QueuedTask
    let index: Int
    let store: TaskQueueStore

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            statusIcon
                .frame(width: 16)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.prompt)
                    .font(.system(size: 10.5, design: .monospaced))
                    .lineLimit(3)
                    .foregroundStyle(task.status == .cancelled ? .tertiary : .primary)

                if let started = task.startedAt, task.status == .running {
                    HStack(spacing: 4) {
                        Text("Running \(elapsedString(from: started))")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                        modelBadge(for: task.model)
                    }
                } else if task.status == .pending {
                    HStack(spacing: 4) {
                        if let target = task.targetPeerName {
                            Text("→ \(target)")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                        modelBadge(for: task.model)
                    }
                }
            }

            Spacer(minLength: 0)

            if task.status == .pending {
                Picker("", selection: Binding(
                    get: { task.model },
                    set: { store.setModel($0, for: task.id) }
                )) {
                    ForEach(TaskModel.allCases) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .font(.system(size: 9))
                .frame(width: 60)

                Button {
                    store.cancel(id: task.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
    }

    private var statusIcon: some View {
        Group {
            switch task.status {
            case .pending:
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
            case .running:
                ProgressView()
                    .scaleEffect(0.55)
                    .frame(width: 14, height: 14)
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            case .cancelled:
                Image(systemName: "minus.circle")
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.system(size: 11))
    }

    @ViewBuilder
    private func modelBadge(for model: TaskModel) -> some View {
        if model != .auto {
            Text(model.displayName)
                .font(.system(size: 8, weight: .medium))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.accentColor.opacity(0.15), in: Capsule())
                .foregroundStyle(Color.accentColor)
        }
    }

    private func elapsedString(from date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        if s < 60 { return "\(s)s" }
        return "\(s / 60)m \(s % 60)s"
    }
}
