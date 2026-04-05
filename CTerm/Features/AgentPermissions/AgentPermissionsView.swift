// AgentPermissionsView.swift
// CTerm
//
// Simple two-mode toggle: "Ask me" or "Trust this session."

import SwiftUI

struct AgentPermissionsView: View {
    @State private var store = AgentPermissionsStore.shared
    @State private var grants = AgentGrantStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Agent Trust", systemImage: "lock.shield")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .tracking(0.5)

            VStack(spacing: 6) {
                trustModeRow(.askMe)
                trustModeRow(.trustSession)
            }

            Text(store.trustMode.description)
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Divider().padding(.vertical, 2)

            grantsSection
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var grantsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Granted Approvals")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .tracking(0.5)

            HStack(spacing: 10) {
                grantStat("Session", count: grants.sessionGrantCount)
                grantStat("Task", count: grants.taskGrantCount)
                grantStat("Repo", count: grants.repoGrantCount)
                Spacer()
            }

            HStack(spacing: 8) {
                Button("Clear session grants") {
                    grants.revokeAllSessionGrants()
                }
                .buttonStyle(.borderless)
                .font(.system(size: 10, design: .rounded))
                .disabled(grants.sessionGrantCount == 0 && grants.taskGrantCount == 0)

                Button("Clear repo grants") {
                    grants.revokeAllRepoGrants()
                }
                .buttonStyle(.borderless)
                .font(.system(size: 10, design: .rounded))
                .disabled(grants.repoGrantCount == 0)
            }
        }
    }

    private func grantStat(_ label: String, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(count)")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 9, design: .rounded))
                .foregroundStyle(.tertiary)
        }
    }

    private func trustModeRow(_ mode: AgentTrustMode) -> some View {
        let isActive = store.trustMode == mode
        return Button {
            store.trustMode = mode
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary.opacity(0.4))
                Image(systemName: mode.icon)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(mode.displayName)
                        .font(.system(size: 12, weight: isActive ? .semibold : .regular, design: .rounded))
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isActive ? Color.accentColor.opacity(0.08) : Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? Color.accentColor.opacity(0.25) : Color.clear, lineWidth: 1)
        )
    }
}
