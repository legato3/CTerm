// ModelRoutingSettingsView.swift
// CTerm
//
// Settings UI for picking the active ModelRoutingPreset. Shows the selected
// preset's role → backend assignments as a read-only table.

import SwiftUI

struct ModelRoutingSettingsView: View {

    @Bindable private var router = ModelRouter.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Preset", selection: $router.activePresetID) {
                ForEach(router.presets) { preset in
                    Text(preset.name).tag(preset.id)
                }
            }
            .pickerStyle(.segmented)

            Text(router.activePreset.description)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Divider()

            assignmentTable(router.activePreset)
        }
        .padding(12)
    }

    private func assignmentTable(_ preset: ModelRoutingPreset) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(StepRole.allCases, id: \.self) { role in
                HStack {
                    Text(role.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 100, alignment: .leading)
                    Spacer()
                    Text(preset.assignments[role]?.displayName ?? "—")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            (preset.assignments[role] == .claudeSubscription ? Color.orange : Color.blue)
                                .opacity(0.12),
                            in: Capsule()
                        )
                }
            }
        }
    }
}
