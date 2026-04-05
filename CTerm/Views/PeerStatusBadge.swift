// PeerStatusBadge.swift
// CTerm
//
// Small peer count indicator for the tab bar area.
// Shows "2 agents" when IPC peers are connected.
// No sidebar required to know agents are running.

import SwiftUI

struct PeerStatusBadge: View {
    let peerCount: Int

    var body: some View {
        if peerCount > 0 {
            HStack(spacing: 3) {
                Circle()
                    .fill(.green)
                    .frame(width: 5, height: 5)
                Text("\(peerCount) agent\(peerCount == 1 ? "" : "s")")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.green.opacity(0.1), in: Capsule())
        }
    }
}
