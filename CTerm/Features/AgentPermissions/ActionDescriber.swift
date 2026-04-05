// ActionDescriber.swift
// CTerm
//
// Populates ActionDescriptor.what/why/impact/rollback from a RiskAssessment
// and the containing session goal. These four fields are the user-facing
// explanation rendered in the approval sheet.

import Foundation

enum ActionDescriber {

    // MARK: - Shell

    static func describeShell(
        command: String,
        assessment: RiskAssessment,
        goal: String?
    ) -> ActionDescriptor {
        let what = "Run: \(command.trimmingCharacters(in: .whitespacesAndNewlines))"
        let why = goal.map { "Toward goal: \($0.prefix(120))" } ?? assessment.explanation
        let impact = impactString(for: assessment)
        return ActionDescriptor(
            what: what,
            why: why,
            impact: impact,
            rollback: assessment.rollbackHint
        )
    }

    // MARK: - Browser

    static func describeBrowser(
        command: String,
        tier: RiskTier,
        goal: String?
    ) -> ActionDescriptor {
        let what = "Browser: \(command.trimmingCharacters(in: .whitespacesAndNewlines))"
        let why = goal.map { "Toward goal: \($0.prefix(120))" } ?? "Drives a browser tab on your behalf"
        let impact = browserImpact(for: tier)
        return ActionDescriptor(what: what, why: why, impact: impact, rollback: nil)
    }

    // MARK: - Hard-stop

    static func describeHardStop(
        command: String,
        reason: HardStopReason,
        assessment: RiskAssessment
    ) -> ActionDescriptor {
        ActionDescriptor(
            what: "Run: \(command.trimmingCharacters(in: .whitespacesAndNewlines))",
            why: reason.headline,
            impact: reason.detail,
            rollback: assessment.rollbackHint
        )
    }

    // MARK: - Private

    private static func impactString(for assessment: RiskAssessment) -> String {
        // Prioritize the highest-weight factors for the impact line.
        let top = assessment.factors
            .sorted { $0.weight > $1.weight }
            .prefix(2)
            .map(\.reason)
        if !top.isEmpty {
            return top.joined(separator: "; ")
        }
        return "\(assessment.category.displayName) action, risk tier \(assessment.tier.label.lowercased())"
    }

    private static func browserImpact(for tier: RiskTier) -> String {
        switch tier {
        case .low:      return "Read-only browser action (snapshot, extract text)"
        case .medium:   return "Interactive browser action (click, type, form fill)"
        case .high:     return "Elevated browser action (script evaluation, file download)"
        case .critical: return "Destructive browser action"
        }
    }
}
