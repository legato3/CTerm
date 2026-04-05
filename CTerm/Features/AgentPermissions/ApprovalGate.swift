// ApprovalGate.swift
// CTerm
//
// Single entry point for action approval. Composes HardStopGuard,
// AgentGrantStore, RiskScorer, and AgentPermissionsStore. Call sites
// replace their individual risk-decision code with one call here.

import Foundation

/// What the gate has to say about dispatching an action.
enum GateDecision {
    case autoApprove
    case hardStop(reason: HardStopReason, context: ApprovalContext, assessment: RiskAssessment)
    case requireApproval(context: ApprovalContext, assessment: RiskAssessment)
    case blocked(reason: String)
}

/// The kind of action being evaluated.
enum ApprovalAction {
    case shellCommand(String)
    case browserAction(command: String, tier: RiskTier)
}

@MainActor
enum ApprovalGate {

    static func evaluate(
        action: ApprovalAction,
        session: AgentSession?,
        pwd: String?,
        gitBranch: String?
    ) -> GateDecision {
        switch action {
        case .shellCommand(let command):
            return evaluateShell(command: command, session: session, pwd: pwd, gitBranch: gitBranch)
        case .browserAction(let command, let tier):
            return evaluateBrowser(command: command, tier: tier, session: session, pwd: pwd)
        }
    }

    // MARK: - Shell

    private static func evaluateShell(
        command: String,
        session: AgentSession?,
        pwd: String?,
        gitBranch: String?
    ) -> GateDecision {
        let assessment = RiskScorer.assess(command: command, pwd: pwd, gitBranch: gitBranch)
        let key = GrantKey.from(command: command, assessment: assessment)

        // 1. Hard-stop always surfaces the sheet.
        if let reason = HardStopGuard.isHardStop(command, gitBranch: gitBranch) {
            let descriptor = ActionDescriber.describeHardStop(command: command, reason: reason, assessment: assessment)
            let ctx = ApprovalContext(
                stepID: session?.currentStepID,
                riskScore: assessment.score,
                riskTier: assessment.tier,
                action: descriptor,
                grantKey: key,
                suggestedScope: .once
            )
            return .hardStop(reason: reason, context: ctx, assessment: assessment)
        }

        // 2. Profile policy (layered above grants & trust mode).
        if let decision = evaluateProfile(
            session: session,
            category: assessment.category,
            tier: assessment.tier,
            assessment: assessment,
            command: command,
            grantKey: key
        ) {
            return decision
        }

        // 3. Existing grant covers this?
        let context = GrantContext(sessionID: session?.id, pwd: pwd)
        if AgentGrantStore.shared.hasGrant(key: key, in: context) {
            return .autoApprove
        }

        // 4. Trust-mode risk decision.
        switch AgentPermissionsStore.shared.decide(for: assessment) {
        case .autoApprove:
            return .autoApprove
        case .blocked(let reason):
            return .blocked(reason: reason)
        case .requireApproval:
            let descriptor = ActionDescriber.describeShell(
                command: command,
                assessment: assessment,
                goal: session?.intent
            )
            let ctx = ApprovalContext(
                stepID: session?.currentStepID,
                riskScore: assessment.score,
                riskTier: assessment.tier,
                action: descriptor,
                grantKey: key,
                suggestedScope: defaultScope(for: assessment)
            )
            return .requireApproval(context: ctx, assessment: assessment)
        }
    }

    // MARK: - Browser

    private static func evaluateBrowser(
        command: String,
        tier: RiskTier,
        session: AgentSession?,
        pwd: String?
    ) -> GateDecision {
        // Browser actions skip RiskScorer and use the caller-supplied tier,
        // since BrowserToolHandler already scores its commands.
        let score = tier.floorScore
        let assessment = RiskAssessment(
            score: score,
            factors: [RiskFactor(kind: .networkExposure, weight: score, reason: "Browser automation")],
            command: command,
            category: .browserAutomation
        )

        let key = GrantKey.browser(tier: tier, tool: command.split(separator: " ").first.map(String.init) ?? command)
        if let decision = evaluateProfile(
            session: session,
            category: .browserAutomation,
            tier: tier,
            assessment: assessment,
            command: command,
            grantKey: key
        ) {
            return decision
        }
        let context = GrantContext(sessionID: session?.id, pwd: pwd)
        if AgentGrantStore.shared.hasGrant(key: key, in: context) {
            return .autoApprove
        }

        switch AgentPermissionsStore.shared.decide(for: assessment) {
        case .autoApprove:
            return .autoApprove
        case .blocked(let reason):
            return .blocked(reason: reason)
        case .requireApproval:
            let descriptor = ActionDescriber.describeBrowser(command: command, tier: tier, goal: session?.intent)
            let ctx = ApprovalContext(
                stepID: session?.currentStepID,
                riskScore: assessment.score,
                riskTier: assessment.tier,
                action: descriptor,
                grantKey: key,
                suggestedScope: .thisTask
            )
            return .requireApproval(context: ctx, assessment: assessment)
        }
    }

    // MARK: - Profile policy

    /// Returns a non-nil decision when the session's profile forces the
    /// outcome (blocked / auto-approve / requireApproval-due-to-cap).
    /// Nil means: fall through to existing grant + trust-mode logic.
    private static func evaluateProfile(
        session: AgentSession?,
        category: AgentActionCategory,
        tier: RiskTier,
        assessment: RiskAssessment,
        command: String,
        grantKey: GrantKey
    ) -> GateDecision? {
        guard let profileID = session?.profileID,
              let profile = AgentProfileStore.shared.profile(id: profileID)
        else { return nil }

        // 1. Blocks win. Render through the approval sheet with scope locked
        //    to .once so the user sees *why* it was refused. The sheet's
        //    "Approve" path still exists as an escape hatch, mirroring how
        //    hard-stops surface.
        if profile.blockedCategories.contains(category) {
            let base = ActionDescriber.describeShell(
                command: command,
                assessment: assessment,
                goal: session?.intent
            )
            let descriptor = ActionDescriptor(
                what: base.what,
                why: "Blocked by profile '\(profile.name)'",
                impact: base.impact,
                rollback: base.rollback
            )
            let ctx = ApprovalContext(
                stepID: session?.currentStepID,
                riskScore: assessment.score,
                riskTier: assessment.tier,
                action: descriptor,
                grantKey: grantKey,
                suggestedScope: .once
            )
            return .requireApproval(context: ctx, assessment: assessment)
        }

        // 2. Risk-tier cap: anything above the cap must show the sheet.
        if tier > profile.maxRiskTier {
            let descriptor = ActionDescriber.describeShell(
                command: command,
                assessment: assessment,
                goal: session?.intent
            )
            let ctx = ApprovalContext(
                stepID: session?.currentStepID,
                riskScore: assessment.score,
                riskTier: assessment.tier,
                action: descriptor,
                grantKey: grantKey,
                suggestedScope: .once
            )
            return .requireApproval(context: ctx, assessment: assessment)
        }

        // 3. Auto-approve when category is whitelisted AND within cap.
        if profile.autoApproveCategories.contains(category) && tier <= profile.maxRiskTier {
            return .autoApprove
        }

        // Otherwise fall through to existing grant/trust-mode logic.
        return nil
    }

    // MARK: - Defaults

    private static func defaultScope(for assessment: RiskAssessment) -> ApprovalScope {
        switch assessment.tier {
        case .low, .medium: return .thisTask
        case .high:         return .thisTask
        case .critical:     return .once
        }
    }
}

// MARK: - Helpers

private extension RiskTier {
    /// Representative numeric score used when we only have the tier.
    var floorScore: Int {
        switch self {
        case .low:      return 10
        case .medium:   return 30
        case .high:     return 60
        case .critical: return 85
        }
    }
}
