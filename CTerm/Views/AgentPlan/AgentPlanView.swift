// AgentPlanView.swift
// CTerm
//
// SwiftUI view that displays a structured agent plan with per-step
// status, approve/skip controls, and a progress indicator.
// Embedded in the compose overlay when an agent plan is active.

import SwiftUI

struct AgentPlanView: View {
    let plan: AgentPlan
    var onApproveStep: (UUID) -> Void
    var onApproveAll: () -> Void
    var onSkipStep: (UUID) -> Void
    var onStop: () -> Void
    var onContinue: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            planHeader
            Divider().opacity(0.3)

            if plan.status == .planning {
                planningState
            } else {
                stepList
                planFooter
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: - Header

    @ViewBuilder
    private var planHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: planStatusIcon)
                .foregroundStyle(planStatusColor)
                .font(.system(size: 12, weight: .medium))
                .symbolEffect(.pulse, isActive: plan.status == .executing || plan.status == .planning)

            Text(plan.displayGoal)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2)
                .foregroundStyle(.primary)

            Spacer()

            if !plan.steps.isEmpty {
                ProgressView(value: plan.progress)
                    .frame(width: 50)
                    .tint(planStatusColor)

                Text("\(plan.completedCount)/\(plan.steps.count)")
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Planning Shimmer

    @ViewBuilder
    private var planningState: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let preview = plan.streamingPreview, !preview.isEmpty {
                Text(preview)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(0..<3, id: \.self) { i in
                    ShimmerRow()
                        .opacity(1.0 - Double(i) * 0.25)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Step List

    @ViewBuilder
    private var stepList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(plan.steps) { step in
                    AgentPlanStepRow(
                        step: step,
                        onApprove: { onApproveStep(step.id) },
                        onSkip: { onSkipStep(step.id) }
                    )
                }
            }
        }
        .frame(maxHeight: 200)
    }

    // MARK: - Footer

    @ViewBuilder
    private var planFooter: some View {
        HStack(spacing: 8) {
            if plan.status.isTerminal {
                if let summary = plan.summary {
                    Text(summary)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                if let onContinue {
                    Button {
                        onContinue("Continue from: \(plan.displayGoal)")
                    } label: {
                        Label("Continue", systemImage: "arrow.right.circle")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.borderless)
                }
            } else {
                if plan.hasUnapprovedSteps {
                    Button {
                        onApproveAll()
                    } label: {
                        Label("Approve All", systemImage: "checkmark.circle")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.borderless)
                }

                Spacer()

                Text(plan.status.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)

                Button {
                    onStop()
                } label: {
                    Label("Stop", systemImage: "stop.circle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Helpers

    private var planStatusIcon: String {
        switch plan.status {
        case .planning:  return "sparkles"
        case .ready:     return "list.bullet.clipboard"
        case .executing: return "play.circle"
        case .paused:    return "pause.circle"
        case .completed: return "checkmark.seal"
        case .failed:    return "exclamationmark.triangle"
        }
    }

    private var planStatusColor: Color {
        switch plan.status {
        case .planning:  return .blue
        case .ready:     return .orange
        case .executing: return .green
        case .paused:    return .yellow
        case .completed: return .green
        case .failed:    return .red
        }
    }
}

// MARK: - Step Row

struct AgentPlanStepRow: View {
    let step: AgentPlanStep
    var onApprove: () -> Void
    var onSkip: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: step.status.icon)
                .font(.system(size: 10))
                .foregroundStyle(stepColor)
                .frame(width: 14)
                .symbolEffect(.pulse, isActive: step.status == .running)

            VStack(alignment: .leading, spacing: 1) {
                Text(step.title)
                    .font(.system(size: 11, weight: step.status == .running ? .medium : .regular))
                    .foregroundStyle(step.status.isTerminal ? .secondary : .primary)
                    .lineLimit(2)
                    .strikethrough(step.status == .skipped)

                if let command = step.command, !command.isEmpty {
                    Text(command)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let output = step.output, !output.isEmpty, step.status == .failed {
                    Text(output.prefix(120))
                        .font(.system(size: 10))
                        .foregroundStyle(.red.opacity(0.8))
                        .lineLimit(2)
                }
            }

            Spacer()

            if let ms = step.durationMs {
                Text(formatDuration(ms))
                    .font(.system(size: 9, weight: .medium).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            if step.status == .pending {
                Button(action: onApprove) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.green)
                }
                .buttonStyle(.borderless)
                .help("Approve this step")

                Button(action: onSkip) {
                    Image(systemName: "forward.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Skip this step")
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(stepBackground)
        )
    }

    private var stepColor: Color {
        switch step.status {
        case .pending:   return .secondary
        case .approved:  return .blue
        case .running:   return .green
        case .succeeded: return .green
        case .failed:    return .red
        case .skipped:   return .secondary
        }
    }

    private var stepBackground: Color {
        switch step.status {
        case .running:   return .blue.opacity(0.06)
        case .failed:    return .red.opacity(0.04)
        default:         return .clear
        }
    }

    private func formatDuration(_ ms: Int) -> String {
        if ms < 1000 { return "\(ms)ms" }
        let seconds = Double(ms) / 1000.0
        return String(format: "%.1fs", seconds)
    }
}

// MARK: - Shimmer

struct ShimmerRow: View {
    @State private var shimmerOffset: CGFloat = -200

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.secondary.opacity(0.15))
                .frame(width: 12, height: 12)

            RoundedRectangle(cornerRadius: 3)
                .fill(Color.secondary.opacity(0.1))
                .frame(height: 10)
                .overlay(
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.15), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .offset(x: shimmerOffset)
                )
                .clipped()
        }
        .padding(.vertical, 3)
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                shimmerOffset = 400
            }
        }
    }
}
