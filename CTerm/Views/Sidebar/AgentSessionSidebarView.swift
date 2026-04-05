import SwiftUI

// MARK: - AgentSessionSidebarView

/// Warp-style agent panel: shows mode, auto-accept toggle, active session status,
/// conversation history, plan steps, and quick actions.
struct AgentSessionSidebarView: View {
    @Bindable var assistant: ComposeAssistantState
    let agentSession: AgentSession?
    let pwd: String?

    @Environment(WindowActions.self) private var actions
    @Environment(\.openURL) private var openURL

    @State private var gitBranch: String?
    @State private var thinkingPulse = false
    @State private var selectedTab: AgentPanelTab = .session

    enum AgentPanelTab: String, CaseIterable {
        case session = "Session"
        case history = "History"
        case changes = "Changes"
    }

    private var isAgentActive: Bool {
        agentSession?.status == .planning || agentSession?.status == .runningCommand || assistant.isBusy
    }

    private var isAwaitingApproval: Bool {
        agentSession?.canApprove == true
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.28)
            tabPicker
            Divider().opacity(0.20)
            tabContent
        }
        .padding(.top, 4)
        .task(id: pwd) {
            guard let pwd, !pwd.isEmpty else { gitBranch = nil; return }
            gitBranch = await TerminalContextGatherer.runTool(
                "git", args: ["branch", "--show-current"], cwd: pwd, timeout: 2
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                // Mode icon + label
                HStack(spacing: 5) {
                    Image(systemName: modeIcon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(modeTint)
                    Text(modeLabel)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }

                Spacer()

                // Thinking indicator
                if isAgentActive {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.purple)
                            .frame(width: 6, height: 6)
                            .opacity(thinkingPulse ? 1.0 : 0.25)
                            .onAppear {
                                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                                    thinkingPulse = true
                                }
                            }
                            .onDisappear { thinkingPulse = false }
                        Text("thinking")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.purple)
                    }
                } else if isAwaitingApproval {
                    Label("needs approval", systemImage: "hand.raised.fill")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.orange)
                }
            }

            // Context chips row
            HStack(spacing: 6) {
                // Mode badge
                Text(assistant.mode.displayName)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(modeTint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(modeTint.opacity(0.12), in: Capsule())

                // Git branch
                if let gitBranch, !gitBranch.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 9))
                        Text(gitBranch)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.10), in: Capsule())
                }

                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(modeTint.opacity(0.04))
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(AgentPanelTab.allCases, id: \.self) { tab in
                Button(action: { selectedTab = tab }) {
                    Text(tab.rawValue)
                        .font(.system(size: 11, weight: selectedTab == tab ? .semibold : .regular, design: .rounded))
                        .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            selectedTab == tab
                                ? Color.white.opacity(0.08)
                                : Color.clear
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .session:
            sessionTab
        case .history:
            historyTab
        case .changes:
            changesTab
        }
    }

    // MARK: - Session Tab

    private var sessionTab: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                // Active Ollama agent session card
                if let agentSession {
                    AgentSessionSidebarCard(
                        session: agentSession,
                        onApprove: { _ = actions.onApproveOllamaAgent?() },
                        onStop: { actions.onStopOllamaAgent?() }
                    )
                }

                // Claude agent quick actions (when no Ollama session but Claude is running)
                if agentSession == nil && assistant.mode == .claudeAgent {
                    claudeAgentCard
                }

                // Empty state
                if agentSession == nil && !assistant.isBusy && assistant.interactions.isEmpty {
                    emptyState
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Claude Agent Card

    private var claudeAgentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.purple)
                Text("Claude Agent")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Spacer()
                if assistant.isBusy {
                    ProgressView().controlSize(.mini).scaleEffect(0.8)
                    Text("working…")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.purple)
                }
            }

            Text("Claude Code is running in a terminal pane. Use the input bar below to send prompts, or use the auto-accept toggle to approve confirmations automatically.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color.purple.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.purple.opacity(0.12), lineWidth: 1))
    }

    // MARK: - History Tab

    private var historyTab: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if assistant.interactions.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "clock")
                            .font(.system(size: 24))
                            .foregroundStyle(.tertiary)
                        Text("No history yet")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                } else {
                    HStack {
                        Spacer()
                        Button("Clear") { assistant.clearHistory() }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                    ForEach(assistant.interactions) { entry in
                        AgentHistoryEntryCard(
                            entry: entry,
                            onEdit: { _ = actions.onApplyComposeAssistantEntry?(entry.id, false) },
                            onRun: { _ = actions.onApplyComposeAssistantEntry?(entry.id, true) },
                            onExplain: { actions.onExplainComposeAssistantEntry?(entry.id) },
                            onFix: { actions.onFixComposeAssistantEntry?(entry.id) }
                        )
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Changes Tab

    private var changesTab: some View {
        FileChangesView(
            onOpenDiff: actions.onOpenDiff,
            onOpenAggregateDiff: actions.onOpenAggregateDiff
        )
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 28))
                .foregroundStyle(.purple.opacity(0.6))

            Text("No active agent session")
                .font(.system(size: 13, weight: .semibold, design: .rounded))

            Text("Use ⌘↩ to start an agent session, or switch the input mode to Agent.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // Mode switcher shortcut
            Button(action: {
                assistant.mode = .claudeAgent
            }) {
                Label("Switch to Agent Mode", systemImage: "sparkles")
                    .font(.system(size: 11, design: .rounded))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.purple)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 24)
    }

    // MARK: - Helpers

    private var modeLabel: String {
        switch assistant.mode {
        case .claudeAgent: return "Agent"
        case .ollamaAgent: return "Local Agent"
        case .ollamaCommand: return "Ollama"
        case .shell: return "Terminal"
        }
    }

    private var modeIcon: String {
        switch assistant.mode {
        case .shell: return "terminal"
        case .ollamaCommand: return "wand.and.stars"
        case .ollamaAgent: return "cpu"
        case .claudeAgent: return "sparkles"
        }
    }

    private var modeTint: Color {
        switch assistant.mode {
        case .claudeAgent, .ollamaAgent: return .purple
        case .ollamaCommand: return .accentColor
        case .shell: return .secondary
        }
    }
}

// MARK: - AgentSessionSidebarCard

private struct AgentSessionSidebarCard: View {
    let session: AgentSession
    let onApprove: () -> Void
    let onStop: () -> Void

    private var statusTint: Color {
        switch session.status {
        case .planning: return .secondary
        case .awaitingApproval: return .orange
        case .runningCommand: return .accentColor
        case .completed: return .green
        case .failed: return .red
        case .stopped: return .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Current Session")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.08)))

                Spacer()

                if session.status == .planning || session.status == .runningCommand {
                    ProgressView().controlSize(.mini).scaleEffect(0.8)
                }

                Text(session.status.label)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(statusTint)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Goal")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                Text(session.displayGoal)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !session.steps.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(session.steps.prefix(8).enumerated()), id: \.element.id) { index, step in
                        AgentSessionStepRow(
                            step: step,
                            isLast: index == session.steps.prefix(8).count - 1
                        )
                    }
                }
            }

            if let pendingCommand = session.pendingCommand,
               !pendingCommand.isEmpty,
               session.canApprove {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Proposed Command", systemImage: "terminal")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.orange)

                    Text(pendingCommand)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

                    HStack(spacing: 8) {
                        Button("Approve & Run", action: onApprove)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .tint(.orange)

                        Button("Stop", action: onStop)
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                        Spacer()
                    }
                }
                .padding(10)
                .background(Color.orange.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.2), lineWidth: 1))
            } else if !session.status.isTerminal {
                HStack {
                    Spacer()
                    Button("Stop Agent", action: onStop)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
        .padding(12)
        .background(Color.purple.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.purple.opacity(0.12), lineWidth: 1))
    }
}

// MARK: - AgentSessionStepRow

private struct AgentSessionStepRow: View {
    let step: OllamaAgentStep
    let isLast: Bool

    private var iconName: String {
        switch step.kind {
        case .goal: return "target"
        case .plan: return "list.bullet"
        case .command: return "terminal"
        case .observation: return "eye"
        case .summary: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        }
    }

    private var tint: Color {
        switch step.kind {
        case .goal: return .purple
        case .plan: return .accentColor
        case .command: return .primary
        case .observation: return .secondary
        case .summary: return .green
        case .error: return .red
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(spacing: 0) {
                Image(systemName: iconName)
                    .font(.system(size: 10))
                    .foregroundStyle(tint)
                    .frame(width: 18, height: 18)
                    .background(tint.opacity(0.1), in: Circle())

                if !isLast {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(step.kind.title)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint.opacity(0.85))
                    .textCase(.uppercase)
                    .tracking(0.5)

                if let command = step.command, !command.isEmpty {
                    Text(command)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !step.text.isEmpty, step.text != step.command {
                    Text(step.text)
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, 8)
        }
    }
}

// MARK: - AgentHistoryEntryCard

private struct AgentHistoryEntryCard: View {
    let entry: ComposeAssistantEntry
    let onEdit: () -> Void
    let onRun: () -> Void
    let onExplain: () -> Void
    let onFix: () -> Void

    private var tint: Color {
        switch entry.status {
        case .failed: return .red
        case .ran, .inserted: return .green
        default: return .accentColor
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(entry.kind.title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(tint.opacity(0.1), in: Capsule())

                if entry.status == .pending {
                    ProgressView().controlSize(.mini).scaleEffect(0.8)
                }

                Spacer()

                Text(entry.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.quaternary)
            }

            Text(entry.displayPrompt)
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.tertiary)
                .lineLimit(2)

            if !entry.primaryText.isEmpty, entry.primaryText != entry.prompt {
                Text(entry.primaryText)
                    .font(entry.usesMonospacedBody
                          ? .system(size: 12, design: .monospaced)
                          : .system(size: 11, design: .rounded))
                    .foregroundStyle(entry.status == .failed ? .red : .primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            }

            if let contextSnippet = entry.contextSnippet, !contextSnippet.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Context")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                    Text(contextSnippet)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(6)
                }
            }

            if entry.canInsert || entry.canRun || entry.canExplain || entry.canFix {
                HStack(spacing: 6) {
                    if entry.canInsert {
                        Button("Edit", action: onEdit).buttonStyle(.bordered).controlSize(.small)
                    }
                    if entry.canRun {
                        Button(entry.kind == .shellDispatch ? "Run Again" : "Run", action: onRun)
                            .buttonStyle(.borderedProminent).controlSize(.small)
                    }
                    if entry.canExplain {
                        Button("Explain", action: onExplain).buttonStyle(.bordered).controlSize(.small)
                    }
                    if entry.canFix {
                        Button("Fix", action: onFix).buttonStyle(.bordered).controlSize(.small)
                    }
                    Spacer()
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }
}
