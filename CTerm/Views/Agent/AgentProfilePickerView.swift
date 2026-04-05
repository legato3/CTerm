// AgentProfilePickerView.swift
// CTerm
//
// Menu button that lets the user pick the active AgentProfile. Sits in the
// compose bar next to the mode selector. Selection updates
// AgentProfileStore.shared.activeProfileID.

import SwiftUI

struct AgentProfilePickerView: View {
    @State private var store = AgentProfileStore.shared

    var body: some View {
        Menu {
            ForEach(store.profiles) { profile in
                Button {
                    store.activeProfileID = profile.id
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(profile.name)
                            Text(profile.description)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: profile.icon)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: store.activeProfile.icon)
                    .font(.system(size: 12, weight: .medium))
                Text(store.activeProfile.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(0.06)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Agent permission profile: \(store.activeProfile.name)")
    }
}
