// TriggerEngineView.swift
// Calyx
//
// Sidebar panel for viewing, enabling/disabling, adding, and removing trigger rules.

import SwiftUI

struct TriggerEngineView: View {
    @State private var engine = TriggerEngine.shared
    @State private var showingAdd = false
    @State private var editingRule: TriggerRule? = nil

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            if engine.rules.isEmpty {
                emptyState
            } else {
                ruleList
            }
        }
        .sheet(isPresented: $showingAdd) {
            RuleEditorSheet(rule: nil) { engine.add($0) }
        }
        .sheet(item: $editingRule) { rule in
            RuleEditorSheet(rule: rule) { engine.update($0) }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Label("Triggers", systemImage: "bolt.fill")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .tracking(0.5)
            Spacer()
            if !engine.rules.isEmpty {
                let active = engine.rules.filter(\.enabled).count
                Text("\(active)/\(engine.rules.count)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            Button(action: { showingAdd = true }) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Add trigger rule")
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    // MARK: - List

    private var ruleList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(engine.rules) { rule in
                    RuleRow(rule: rule) {
                        engine.toggle(id: rule.id)
                    } onEdit: {
                        editingRule = rule
                    } onDelete: {
                        engine.remove(id: rule.id)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "bolt.slash")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("No trigger rules")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                exampleLine("When command fails → Route to Claude")
                exampleLine("When tests fail → Desktop notification")
                exampleLine("When agent connects → Advance queue")
            }
            .padding(.top, 4)
            Button("Add first rule") { showingAdd = true }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.blue)
                .padding(.top, 6)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private func exampleLine(_ text: String) -> some View {
        Label(text, systemImage: "bolt")
            .font(.system(size: 10, design: .rounded))
            .foregroundStyle(.tertiary)
    }
}

// MARK: - Rule row

private struct RuleRow: View {
    let rule: TriggerRule
    var onToggle: (() -> Void)?
    var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(get: { rule.enabled }, set: { _ in onToggle?() }))
                .toggleStyle(.switch)
                .scaleEffect(0.7)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(rule.enabled ? .primary : .tertiary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: rule.triggerType.icon)
                        .font(.system(size: 9))
                    Text(rule.triggerType.displayName)
                    Text("→")
                    Image(systemName: rule.actionType.icon)
                        .font(.system(size: 9))
                    Text(rule.actionType.displayName)
                }
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.tertiary)
            }

            Spacer()

            if isHovering {
                HStack(spacing: 2) {
                    Button(action: { onEdit?() }) {
                        Image(systemName: "pencil")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Edit rule")

                    Button(action: { onDelete?() }) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Delete rule")
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(isHovering ? 0.07 : 0.04))
        )
        .onAssumeInsideHover($isHovering)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
    }
}

// MARK: - Rule editor sheet

private struct RuleEditorSheet: View {
    let existingRule: TriggerRule?
    var onSave: ((TriggerRule) -> Void)?

    @State private var name: String
    @State private var triggerType: TriggerType
    @State private var actionType: ActionType
    @State private var actionMessage: String
    @State private var notifyTitle: String
    @State private var notifyBody: String
    @State private var memoryKey: String
    @State private var memoryValue: String

    @Environment(\.dismiss) private var dismiss

    init(rule: TriggerRule?, onSave: ((TriggerRule) -> Void)?) {
        self.existingRule = rule
        self.onSave = onSave
        _name          = State(initialValue: rule?.name ?? "")
        _triggerType   = State(initialValue: rule?.triggerType ?? .commandFail)
        _actionType    = State(initialValue: rule?.actionType ?? .routeToClaude)
        _actionMessage = State(initialValue: rule?.actionMessage ?? "")
        _notifyTitle   = State(initialValue: rule?.notifyTitle ?? "")
        _notifyBody    = State(initialValue: rule?.notifyBody ?? "")
        _memoryKey     = State(initialValue: rule?.memoryKey ?? "")
        _memoryValue   = State(initialValue: rule?.memoryValue ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(existingRule == nil ? "Add Trigger Rule" : "Edit Trigger Rule")
                .font(.system(size: 16, weight: .semibold, design: .rounded))

            field("Name") {
                TextField("e.g. Route errors to Claude", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            field("When…") {
                Picker("Trigger", selection: $triggerType) {
                    ForEach(TriggerType.allCases, id: \.self) { t in
                        Label(t.displayName, systemImage: t.icon).tag(t)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            field("Do…") {
                Picker("Action", selection: $actionType) {
                    ForEach(ActionType.allCases, id: \.self) { a in
                        Label(a.displayName, systemImage: a.icon).tag(a)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            actionFields

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    @ViewBuilder
    private var actionFields: some View {
        switch actionType {
        case .routeToClaude:
            field("Message (optional)") {
                TextEditor(text: $actionMessage)
                    .font(.system(size: 11, design: .rounded))
                    .frame(minHeight: 60, maxHeight: 120)
                    .border(Color.secondary.opacity(0.3), width: 0.5)
                    .cornerRadius(4)
                Text("Leave blank for an auto-generated message. Use {snippet}, {test_names}, or {peer_name} as placeholders.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        case .notify:
            field("Title") {
                TextField("Notification title (or leave blank)", text: $notifyTitle)
                    .textFieldStyle(.roundedBorder)
            }
            field("Body") {
                TextField("Notification body (or leave blank)", text: $notifyBody)
                    .textFieldStyle(.roundedBorder)
            }
        case .advanceQueue:
            Text("The task queue will advance to the next pending task when this trigger fires.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .remember:
            field("Memory Key") {
                TextField("e.g. last-error", text: $memoryKey)
                    .textFieldStyle(.roundedBorder)
            }
            field("Memory Value") {
                TextField("Value to store (supports {snippet}, {peer_name}…)", text: $memoryValue)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private func field<C: View>(_ label: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }

    private func save() {
        var rule = existingRule ?? TriggerRule(
            name: "",
            triggerType: triggerType,
            actionType: actionType
        )
        rule.name          = name.trimmingCharacters(in: .whitespacesAndNewlines)
        rule.triggerType   = triggerType
        rule.actionType    = actionType
        rule.actionMessage = actionMessage
        rule.notifyTitle   = notifyTitle
        rule.notifyBody    = notifyBody
        rule.memoryKey     = memoryKey
        rule.memoryValue   = memoryValue
        onSave?(rule)
        dismiss()
    }
}
