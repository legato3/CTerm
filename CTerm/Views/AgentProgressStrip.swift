// AgentProgressStrip.swift
// CTerm
//
// Always-visible compact strip when any agent work is happening.
// Shows: phase label, step progress, and a red stop button.
// Replaces the need to open a sidebar to see agent status.

import SwiftUI

struct AgentProgressStrip: View {
    let session: AgentSession
    let onStop: () -> Void
    let onApprove: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            // Phase indicator
            if session.phase.isActive {
                ProgressView()
                    .controlSize(.mini)
            } else if session.phase == .failed {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
            } else if session.phase == .completed {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.green)
            }

            // Progress label
            Text(session.progressLabel)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .lineLimit(1)
                .foregroundStyle(.primary)

            Spacer()

            // Progress bar
            if !(session.plan?.steps.isEmpty ?? true) && session.phase.isActive {
                ProgressView(value: session.progress)
                    .progressViewStyle(.linear)
                    .frame(width: 60)
                    .tint(.accentColor)
            }

            // Approve button (when awaiting approval)
            if session.phase == .awaitingApproval, let onApprove {
                Button(action: onApprove) {
                    Text("Approve")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
            }

            // Stop button — always visible when active
            if !session.phase.isTerminal {
                Button(action: onStop) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .frame(width: 18, height: 18)
                .background(Circle().fill(.red))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
