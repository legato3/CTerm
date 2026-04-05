// AgentProfilesSettingsView.swift
// CTerm
//
// Master-detail settings panel for viewing, creating, editing, duplicating
// and deleting AgentProfile values. Built-in profiles are rendered read-only.
// Custom profiles persist via AgentProfileStore.shared.

import SwiftUI

@MainActor
struct AgentProfilesSettingsView: View {

    @Bindable private var store = AgentProfileStore.shared

    @State private var selectedID: UUID? = AgentProfileStore.shared.activeProfileID
    @State private var draft: AgentProfile?
    @State private var iconPickerPresented = false

    private static let riskTiers: [RiskTier] = [.low, .medium, .high, .critical]

    private static let iconChoices: [String] = [
        "shield", "eye", "folder.badge.gearshape", "slider.horizontal.3",
        "bolt.fill", "hand.raised", "lock.shield", "gearshape",
        "terminal", "paperplane", "hammer", "wand.and.stars",
        "person.crop.circle", "star", "flag", "flame",
        "leaf", "bell", "cube", "square.grid.2x2"
    ]

    // MARK: - Body

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            listColumn
                .frame(width: 220)
            Divider()
            detailColumn
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 640, minHeight: 460)
        .onAppear { syncDraft() }
        .onChange(of: selectedID) { _, _ in syncDraft() }
    }

    // MARK: - List column

    private var listColumn: some View {
        VStack(spacing: 0) {
            List(selection: $selectedID) {
                ForEach(store.profiles) { profile in
                    listRow(profile)
                        .tag(Optional(profile.id))
                }
            }
            .listStyle(.sidebar)

            Divider()

            HStack(spacing: 4) {
                Button {
                    addCustomProfile()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.borderless)
                .help("Add a new custom profile")

                Button {
                    deleteSelectedProfile()
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.borderless)
                .disabled(!canDeleteSelected)
                .help("Delete selected profile")

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }

    private func listRow(_ profile: AgentProfile) -> some View {
        HStack(spacing: 8) {
            Image(systemName: profile.icon)
                .frame(width: 18)
                .foregroundStyle(.secondary)
            Text(profile.name)
                .lineLimit(1)
            if profile.id == store.activeProfileID {
                Text("●")
                    .foregroundStyle(.tint)
                    .font(.system(size: 8))
            }
            Spacer()
            if profile.isBuiltIn {
                Text("Built-in")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
            }
        }
    }

    // MARK: - Detail column

    @ViewBuilder
    private var detailColumn: some View {
        if let draft {
            Form {
                editorSections(draft: draft)
            }
            .formStyle(.grouped)
            .padding(.bottom, 8)
            .overlay(alignment: .bottom) {
                footer
            }
        } else {
            VStack {
                Spacer()
                Text("Select a profile to view or edit.")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func editorSections(draft: AgentProfile) -> some View {
        let readOnly = draft.isBuiltIn

        Section("Profile") {
            LabeledContent("Name") {
                TextField("Name", text: nameBinding)
                    .textFieldStyle(.roundedBorder)
                    .disabled(readOnly)
            }
            LabeledContent("Description") {
                TextField("Description", text: descriptionBinding, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
                    .disabled(readOnly)
            }
            LabeledContent("Icon") {
                HStack(spacing: 8) {
                    Image(systemName: draft.icon)
                        .frame(width: 20)
                    Button {
                        if !readOnly { iconPickerPresented = true }
                    } label: {
                        HStack {
                            Text(draft.icon).font(.system(.body, design: .monospaced))
                            Image(systemName: "chevron.down").font(.caption)
                        }
                    }
                    .disabled(readOnly)
                    .popover(isPresented: $iconPickerPresented) {
                        iconGridPopover
                    }
                    Spacer()
                }
            }
        }

        Section("Permissions") {
            LabeledContent("Trust mode") {
                Picker("", selection: trustModeBinding) {
                    Text("Ask me").tag(AgentTrustMode.askMe)
                    Text("Trust session").tag(AgentTrustMode.trustSession)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .disabled(readOnly)
            }
            LabeledContent("Max risk tier") {
                Picker("", selection: maxRiskTierBinding) {
                    ForEach(Self.riskTiers, id: \.self) { tier in
                        Text(tier.label).tag(tier)
                    }
                }
                .labelsHidden()
                .disabled(readOnly)
            }
        }

        Section("Auto-approve categories") {
            ForEach(AgentActionCategory.allCases, id: \.self) { cat in
                Toggle(isOn: autoApproveBinding(cat)) {
                    HStack(spacing: 6) {
                        Image(systemName: cat.icon).frame(width: 18)
                        Text(cat.displayName)
                    }
                }
                .disabled(readOnly)
            }
        }

        Section("Blocked categories") {
            ForEach(AgentActionCategory.allCases, id: \.self) { cat in
                Toggle(isOn: blockedBinding(cat)) {
                    HStack(spacing: 6) {
                        Image(systemName: cat.icon).frame(width: 18)
                        Text(cat.displayName)
                    }
                }
                .disabled(readOnly)
            }
        }

        if !conflictingCategories(draft).isEmpty {
            Section {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(conflictingCategories(draft), id: \.self) { cat in
                            Text("Category \"\(cat.displayName)\" is both auto-approved and blocked — blocks wins.")
                                .font(.caption)
                        }
                    }
                    Spacer()
                }
            }
        }
    }

    private var iconGridPopover: some View {
        let columns = Array(repeating: GridItem(.fixed(36), spacing: 6), count: 5)
        return ScrollView {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Self.iconChoices, id: \.self) { symbol in
                    Button {
                        updateDraft { $0.icon = symbol }
                        iconPickerPresented = false
                    } label: {
                        Image(systemName: symbol)
                            .font(.system(size: 16))
                            .frame(width: 32, height: 32)
                            .background(
                                (draft?.icon == symbol ? Color.accentColor.opacity(0.25) : Color.clear),
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
        }
        .frame(width: 210, height: 180)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            if let draft {
                Button("Set as active") {
                    store.activeProfileID = draft.id
                }
                .disabled(draft.id == store.activeProfileID)

                Button("Duplicate") {
                    duplicate(draft)
                }

                Spacer()

                if !draft.isBuiltIn {
                    Button("Revert changes") {
                        syncDraft()
                    }
                    .disabled(!isDirty)

                    Button("Save") {
                        saveDraft()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isDirty || draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - State helpers

    private var canDeleteSelected: Bool {
        guard let id = selectedID, let p = store.profile(id: id) else { return false }
        return !p.isBuiltIn
    }

    private var isDirty: Bool {
        guard let draft, let stored = store.profile(id: draft.id) else { return false }
        return stored != draft
    }

    private func syncDraft() {
        guard let id = selectedID, let p = store.profile(id: id) else {
            draft = nil
            return
        }
        draft = p
    }

    private func updateDraft(_ mutate: (inout AgentProfile) -> Void) {
        guard var d = draft else { return }
        mutate(&d)
        draft = d
    }

    private func saveDraft() {
        guard let d = draft, !d.isBuiltIn else { return }
        do {
            try store.update(d)
        } catch {
            NSSound.beep()
        }
    }

    private func addCustomProfile() {
        let template: AgentProfile = {
            if let id = selectedID, let p = store.profile(id: id) { return p }
            return AgentProfile.standard
        }()
        let newProfile = AgentProfile(
            name: "\(template.name) Copy",
            description: template.description,
            icon: template.icon,
            trustMode: template.trustMode,
            autoApproveCategories: template.autoApproveCategories,
            blockedCategories: template.blockedCategories,
            maxRiskTier: template.maxRiskTier,
            isBuiltIn: false
        )
        if store.add(newProfile) {
            selectedID = newProfile.id
        }
    }

    private func deleteSelectedProfile() {
        guard let id = selectedID else { return }
        do {
            try store.delete(id: id)
            selectedID = store.profiles.first?.id
        } catch {
            NSSound.beep()
        }
    }

    private func duplicate(_ source: AgentProfile) {
        let copy = AgentProfile(
            name: "\(source.name) Copy",
            description: source.description,
            icon: source.icon,
            trustMode: source.trustMode,
            autoApproveCategories: source.autoApproveCategories,
            blockedCategories: source.blockedCategories,
            maxRiskTier: source.maxRiskTier,
            isBuiltIn: false
        )
        if store.add(copy) {
            selectedID = copy.id
        }
    }

    private func conflictingCategories(_ p: AgentProfile) -> [AgentActionCategory] {
        AgentActionCategory.allCases.filter {
            p.autoApproveCategories.contains($0) && p.blockedCategories.contains($0)
        }
    }

    // MARK: - Bindings

    private var nameBinding: Binding<String> {
        Binding(get: { draft?.name ?? "" }, set: { v in updateDraft { $0.name = v } })
    }

    private var descriptionBinding: Binding<String> {
        Binding(get: { draft?.description ?? "" }, set: { v in updateDraft { $0.description = v } })
    }

    private var trustModeBinding: Binding<AgentTrustMode> {
        Binding(
            get: { draft?.trustMode ?? .askMe },
            set: { v in updateDraft { $0.trustMode = v } }
        )
    }

    private var maxRiskTierBinding: Binding<RiskTier> {
        Binding(
            get: { draft?.maxRiskTier ?? .low },
            set: { v in updateDraft { $0.maxRiskTier = v } }
        )
    }

    private func autoApproveBinding(_ cat: AgentActionCategory) -> Binding<Bool> {
        Binding(
            get: { draft?.autoApproveCategories.contains(cat) ?? false },
            set: { on in
                updateDraft {
                    if on { $0.autoApproveCategories.insert(cat) }
                    else { $0.autoApproveCategories.remove(cat) }
                }
            }
        )
    }

    private func blockedBinding(_ cat: AgentActionCategory) -> Binding<Bool> {
        Binding(
            get: { draft?.blockedCategories.contains(cat) ?? false },
            set: { on in
                updateDraft {
                    if on { $0.blockedCategories.insert(cat) }
                    else { $0.blockedCategories.remove(cat) }
                }
            }
        )
    }
}
