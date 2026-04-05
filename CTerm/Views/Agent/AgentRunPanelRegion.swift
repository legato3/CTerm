// AgentRunPanelRegion.swift
// CTerm
//
// Container placed between the terminal area and the compose bar. Reads the
// active tab's inline AgentSession (via Tab.ollamaAgentSession) and renders
// card / strip / nothing based on state.

import SwiftUI

struct AgentRunPanelRegion: View {
    let activeTab: Tab?
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
                        onSkipStep: { skipStep(id: $0, in: session) }
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
    /// Other session kinds still have dedicated sidebars, but the window-level
    /// actions here only know how to drive `Tab.ollamaAgentSession`.
    private var displayedSession: AgentSession? {
        _ = tick  // re-read on timer fire
        guard let tab = activeTab else { return nil }
        guard let inline = tab.ollamaAgentSession, !inline.phase.isTerminal else { return nil }
        return inline
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
