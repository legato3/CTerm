// ApprovalScopePicker.swift
// CTerm
//
// Radio-button group for picking an approval scope.
// Disabled (only .once selectable) for hard-stop actions.

import SwiftUI

struct ApprovalScopePicker: View {
    @Binding var selection: ApprovalScope
    let isHardStop: Bool

    private var availableScopes: [ApprovalScope] {
        isHardStop ? [.once] : [.once, .thisTask, .thisRepo, .thisSession]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Scope")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(availableScopes, id: \.self) { scope in
                HStack(spacing: 8) {
                    Image(systemName: selection == scope ? "circle.inset.filled" : "circle")
                        .foregroundStyle(selection == scope ? Color.accentColor : .secondary)
                    Text(label(for: scope))
                        .font(.callout)
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture { selection = scope }
                .padding(.vertical, 2)
            }
            if isHardStop {
                Text("This action is blocked from broader scopes.")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .padding(.top, 2)
            }
        }
    }

    private func label(for scope: ApprovalScope) -> String {
        switch scope {
        case .once:         return "Just this once"
        case .thisTask:     return "For this task"
        case .thisRepo:     return "For this repo"
        case .thisSession:  return "For this app session"
        }
    }
}
