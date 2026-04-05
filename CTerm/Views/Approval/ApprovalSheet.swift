// ApprovalSheet.swift
// CTerm
//
// Modal sheet that surfaces an ApprovalContext to the user. Shows the full
// action descriptor (what / why / impact / rollback), a risk badge, and a
// scope picker. Hard-stop actions render red and force `.once` scope.

import SwiftUI

struct ApprovalSheet: View {
    let context: ApprovalContext
    let hardStop: HardStopReason?
    var onResolve: (ApprovalAnswer, ApprovalScope) -> Void
    var onDismiss: () -> Void

    @State private var scope: ApprovalScope

    init(
        context: ApprovalContext,
        hardStop: HardStopReason? = nil,
        onResolve: @escaping (ApprovalAnswer, ApprovalScope) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.context = context
        self.hardStop = hardStop
        self.onResolve = onResolve
        self.onDismiss = onDismiss
        self._scope = State(initialValue: hardStop != nil ? .once : context.suggestedScope)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            descriptorRows
            Divider()
            riskRow
            Divider()
            ApprovalScopePicker(selection: $scope, isHardStop: hardStop != nil)
            Divider()
            buttons
        }
        .padding(18)
        .frame(width: 440)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: hardStop != nil ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(hardStop != nil ? Color.red : accentForTier(context.riskTier))
            Text(hardStop != nil ? "Hard Stop — Confirm Once" : "Approval Needed")
                .font(.headline)
            Spacer()
        }
    }

    private var descriptorRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            row(label: "WHAT", value: context.action.what, mono: true)
            row(label: "WHY", value: context.action.why)
            row(label: "IMPACT", value: context.action.impact)
            if let rollback = context.action.rollback {
                row(label: "ROLLBACK", value: rollback, mono: true)
            }
            if let hardStop {
                row(label: "REASON", value: hardStop.detail)
            }
        }
    }

    private var riskRow: some View {
        HStack(spacing: 8) {
            Image(systemName: context.riskTier.icon)
                .foregroundStyle(accentForTier(context.riskTier))
            Text("\(context.riskTier.label) (\(context.riskScore))")
                .font(.callout.weight(.medium))
            Spacer()
        }
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            Button("Deny") { onResolve(.denied, .once) }
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button("Dismiss") { onDismiss() }
            Button(hardStop != nil ? "Approve once" : "Approve") {
                onResolve(.approved, scope)
            }
            .buttonStyle(.borderedProminent)
            .tint(hardStop != nil ? .red : accentForTier(context.riskTier))
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Helpers

    private func row(label: String, value: String, mono: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 68, alignment: .trailing)
            Text(value)
                .font(mono ? .system(.callout, design: .monospaced) : .callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func accentForTier(_ tier: RiskTier) -> Color {
        switch tier {
        case .low:      return .green
        case .medium:   return .yellow
        case .high:     return .orange
        case .critical: return .red
        }
    }
}
