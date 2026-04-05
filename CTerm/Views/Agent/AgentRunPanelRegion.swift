// AgentRunPanelRegion.swift
// CTerm
//
// Container placed between the terminal area and the compose bar. Reads the
// active tab's inline AgentSession (via Tab.ollamaAgentSession) and renders
// card / strip / nothing based on state.

import SwiftUI

struct AgentRunPanelRegion: View {
    let activeTab: Tab?
    var composeState: ComposeAssistantState?
    var onApprove: () -> Void
    var onStop: () -> Void
    var onDeny: () -> Void
    var onDismiss: () -> Void

    /// Driven by a 1-second timer so the elapsed-time label updates.
    @State private var tick: Int = 0
    @State private var timer: Timer?

    var body: some View {
        Group {
            if let session = displayedSession {
                if session.isRunPanelCollapsed {
                    AgentRunPanelStrip(
                        session: session,
                        onExpand: { session.isRunPanelCollapsed = false },
                        onStop: onStop
                    )
                } else {
                    AgentRunPanelView(
                        session: session,
                        onCollapse: { session.isRunPanelCollapsed = true },
                        onStop: onStop,
                        onApprove: onApprove,
                        onDeny: onDeny,
                        onDismiss: onDismiss,
                        onApproveSafe: { approveSafe(in: session) },
                        onApproveStep: { approveStep(id: $0, in: session) },
                        onSkipStep: { skipStep(id: $0, in: session) },
                        onSaveFinding: { saveFinding($0, in: session) },
                        onSaveAllFindings: { saveAllFindings(in: session) },
                        onNextAction: { prefillCompose(with: $0.prompt) },
                        onContinue: { continueFromHandoff(session: session) },
                        handoffGoalPreview: handoffGoalPreview(for: session),
                        workingDir: activeTab?.pwd
                    )
                }
            } else {
                EmptyView()
            }
        }
        .onAppear(perform: startTimer)
        .onDisappear(perform: stopTimer)
    }

    // MARK: - Selection

    /// Only inline compose-driven sessions are controllable from this region.
    /// Terminal sessions remain visible so the user can review summary +
    /// browser findings until they explicitly dismiss.
    private var displayedSession: AgentSession? {
        _ = tick  // re-read on timer fire
        guard let tab = activeTab else { return nil }
        return tab.ollamaAgentSession
    }

    // MARK: - Per-step approval

    private func approveStep(id: UUID, in session: AgentSession) {
        guard let plan = session.plan, let idx = plan.steps.firstIndex(where: { $0.id == id }) else { return }
        if plan.steps[idx].status == .pending {
            plan.steps[idx].status = .approved
        }
        maybeStartExecuting(plan: plan)
    }

    private func skipStep(id: UUID, in session: AgentSession) {
        guard let plan = session.plan, let idx = plan.steps.firstIndex(where: { $0.id == id }) else { return }
        if plan.steps[idx].status == .pending || plan.steps[idx].status == .approved {
            plan.steps[idx].status = .skipped
        }
        maybeStartExecuting(plan: plan)
    }

    private func approveSafe(in session: AgentSession) {
        guard let plan = session.plan else { return }
        for i in plan.steps.indices
            where plan.steps[i].status == .pending && !plan.steps[i].willAsk {
            plan.steps[i].status = .approved
        }
        maybeStartExecuting(plan: plan)
    }

    /// If every step has been resolved (approved/skipped/terminal) and the plan
    /// is still in ready state, flip it to executing so ExecutionCoordinator picks up.
    private func maybeStartExecuting(plan: AgentPlan) {
        let anyPending = plan.steps.contains { $0.status == .pending }
        if !anyPending && plan.status == .ready {
            plan.status = .executing
        }
    }

    // MARK: - Browser finding handoff

    private func saveFinding(_ finding: BrowserFinding, in session: AgentSession) {
        persistFinding(finding, in: session)
        session.keptFindingIDs.insert(finding.id)
    }

    private func saveAllFindings(in session: AgentSession) {
        guard let research = session.browserResearchSession else { return }
        for finding in research.findings where !session.keptFindingIDs.contains(finding.id) {
            persistFinding(finding, in: session)
            session.keptFindingIDs.insert(finding.id)
        }
    }

    private func persistFinding(_ finding: BrowserFinding, in session: AgentSession) {
        let pwd = activeTab?.pwd ?? TerminalControlBridge.shared.delegate?.activeTabPwd
        guard let pwd else { return }
        let host = URL(string: finding.url)?.host ?? "unknown"
        let key = "browser/\(host)/\(finding.title.prefix(40))"
        AgentMemoryStore.shared.remember(
            projectKey: AgentMemoryStore.key(for: pwd),
            key: key,
            value: String(finding.content.prefix(2000)),
            ttlDays: 30,
            category: .projectFact,
            importance: 0.6,
            confidence: 0.8,
            source: .browserResearch
        )
    }

    // MARK: - Next-action / continue handoff

    private func prefillCompose(with text: String) {
        guard let composeState else { return }
        composeState.draftText = text
    }

    private func handoffGoalPreview(for session: AgentSession) -> String? {
        // Only meaningful after the session completes — before that, the
        // handoff stored in memory is from an earlier session.
        guard session.phase.isTerminal else { return nil }
        guard let pwd = activeTab?.pwd ?? TerminalControlBridge.shared.delegate?.activeTabPwd else { return nil }
        let projectKey = AgentMemoryStore.key(for: pwd)
        guard let handoff = AgentMemoryStore.shared.lastHandoff(projectKey: projectKey) else { return nil }
        // The stored value looks like: "Goal: X\nSteps: N/M\nFiles: …\nOutcome: …"
        let goalLine = handoff.value.split(separator: "\n")
            .first(where: { $0.hasPrefix("Goal:") })
            .map { String($0.dropFirst(5).trimmingCharacters(in: .whitespaces)) }
        guard let goal = goalLine, !goal.isEmpty, goal != session.displayIntent else { return nil }
        return goal
    }

    private func continueFromHandoff(session: AgentSession) {
        guard let goal = handoffGoalPreview(for: session) else { return }
        prefillCompose(with: "Continue from: \(goal)")
    }

    // MARK: - Timer

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in tick &+= 1 }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
