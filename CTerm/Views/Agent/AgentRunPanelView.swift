// AgentRunPanelView.swift
// CTerm
//
// The card form of the agent run panel. Shows goal, phase, plan stepper,
// current command, last observation, and primary buttons. Tap the header
// to collapse back to the strip.

import SwiftUI

struct AgentRunPanelView: View {
    let session: AgentSession
    var onCollapse: () -> Void
    var onStop: () -> Void
    var onApprove: () -> Void
    var onDeny: () -> Void
    var onDismiss: () -> Void
    var onApproveSafe: (() -> Void)? = nil
    var onApproveStep: ((UUID) -> Void)? = nil
    var onSkipStep: ((UUID) -> Void)? = nil
    var onSaveFinding: ((BrowserFinding) -> Void)? = nil
    var onSaveAllFindings: (() -> Void)? = nil
    var onNextAction: ((NextAction) -> Void)? = nil
    var onContinue: (() -> Void)? = nil
    var handoffGoalPreview: String? = nil

    @State private var showMemoriesPopover: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            statusLine
            if let plan = session.plan, !plan.steps.isEmpty {
                Divider()
                AgentRunPlanStepper(
                    steps: plan.steps,
                    awaitingApproval: session.phase == .awaitingApproval,
                    onApproveStep: onApproveStep,
                    onSkipStep: onSkipStep
                )
            }
            if !recentInlineEvents.isEmpty {
                Divider()
                activityTranscript
            }
            if session.phase == .awaitingApproval, let command = session.pendingCommand {
                Divider()
                approvalBlock(command: command)
            } else if session.phase.isActive {
                Divider()
                runningBlock
            } else if session.phase.isTerminal {
                Divider()
                summaryBlock
            }
            if let research = session.browserResearchSession {
                Divider()
                browserResearchBlock(research)
            }
            buttonsRow
        }
        .padding(10)
        .background(.ultraThinMaterial)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: iconForKind)
                .font(.system(size: 12))
                .foregroundStyle(Color.accentColor)
                .frame(width: 16)
            Text(session.intent)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .truncationMode(.tail)
            if !session.memoryKeysUsed.isEmpty {
                Button {
                    showMemoriesPopover.toggle()
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "brain.head.profile").font(.system(size: 8))
                        Text("\(session.memoryKeysUsed.count)")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.purple)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.purple.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .help("\(session.memoryKeysUsed.count) memory entries informed this session")
                .popover(isPresented: $showMemoriesPopover, arrowEdge: .bottom) {
                    memoriesPopover
                }
            }
            if let rule = session.triggeredBy {
                HStack(spacing: 2) {
                    Image(systemName: "bolt.fill").font(.system(size: 8))
                    Text(rule)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .lineLimit(1)
                }
                .foregroundStyle(.yellow)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.yellow.opacity(0.12), in: Capsule())
                .help("Triggered by rule: \(rule)")
            }
            Spacer(minLength: 8)
            Button(action: onCollapse) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onCollapse)
    }

    private var iconForKind: String {
        switch session.kind {
        case .inline:     return "terminal"
        case .multiStep:  return "list.bullet.rectangle"
        case .queued:     return "tray.and.arrow.down"
        case .delegated:  return "arrow.triangle.branch"
        }
    }

    // MARK: - Status line

    private var statusLine: some View {
        HStack(spacing: 6) {
            phaseBadge
            Text("•")
                .foregroundStyle(.tertiary)
            Text(session.progressLabel)
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            Text(elapsedString)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

    private var phaseBadge: some View {
        HStack(spacing: 4) {
            if session.phase.isActive {
                ProgressView().controlSize(.mini)
            }
            Text(session.phase.userLabel)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(phaseColor)
        }
    }

    private var phaseColor: Color {
        switch session.phase {
        case .idle:             return .secondary
        case .thinking:         return .blue
        case .awaitingApproval: return .orange
        case .running:          return .teal
        case .summarizing:      return .indigo
        case .completed:        return .green
        case .failed:           return .red
        case .cancelled:        return .secondary
        }
    }

    private var elapsedString: String {
        let seconds = Int(session.elapsedSeconds)
        if seconds < 60 { return "\(seconds)s" }
        return "\(seconds / 60)m \(seconds % 60)s"
    }

    // MARK: - Running block

    private var runningBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let running = session.plan?.steps.first(where: { $0.status == .running }),
               let command = running.command {
                HStack(spacing: 6) {
                    Text("$")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Text(command)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            if let lastObs = lastObservation {
                Text(lastObs)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
        }
    }

    /// True when the plan has at least one safe pending step + at least one risky one,
    /// so the "Approve Safe" shortcut is meaningful.
    private var hasSafeSteps: Bool {
        guard let steps = session.plan?.steps else { return false }
        let pending = steps.filter { $0.status == .pending }
        let safe = pending.filter { !$0.willAsk }
        let risky = pending.filter { $0.willAsk }
        return !safe.isEmpty && !risky.isEmpty
    }

    private var lastObservation: String? {
        let artifactText = session.artifacts
            .last(where: { $0.kind == .commandOutput })?
            .value
        if let artifactText, !artifactText.isEmpty { return artifactText }
        return session.inlineSteps.first(where: { $0.kind == .observation })?.text
    }

    private var recentInlineEvents: [InlineAgentStep] {
        Array(session.inlineSteps.prefix(8).reversed())
    }

    private var activityTranscriptTitle: String {
        recentInlineEvents.contains(where: { $0.kind == .observation || $0.kind == .command })
            ? "Session Output"
            : "Session Log"
    }

    private var activityTranscript: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(activityTranscriptTitle)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(recentInlineEvents.count) event\(recentInlineEvents.count == 1 ? "" : "s")")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.tertiary)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(recentInlineEvents) { step in
                        InlineAgentTranscriptRow(step: step)
                    }
                }
            }
            .frame(maxHeight: 220)
        }
    }

    // MARK: - Approval block

    private func approvalBlock(command: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Awaiting approval")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.orange)
            HStack(spacing: 6) {
                Text("$")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Text(command)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
        }
    }

    // MARK: - Summary block

    private var summaryBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            exitStatusLine
            if !filesChanged.isEmpty {
                filesChangedList
            }
            if !failedSteps.isEmpty {
                failedStepsBlock
            }
            if !nextActions.isEmpty || handoffGoalPreview != nil {
                nextActionsBlock
            }
            if let err = session.errorMessage, session.result == nil {
                Text(err)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }
        }
    }

    private var exitStatusLine: some View {
        HStack(spacing: 6) {
            Image(systemName: exitIcon)
                .font(.system(size: 10))
                .foregroundStyle(exitTint)
            Text(exitHeadline)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(exitTint)
            Spacer(minLength: 0)
        }
    }

    private var filesChangedList: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Files changed (\(filesChanged.count))")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.tertiary)
            ForEach(Array(filesChanged.prefix(5).enumerated()), id: \.offset) { _, path in
                HStack(spacing: 4) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Text((path as NSString).lastPathComponent)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(path)
                }
            }
            if filesChanged.count > 5 {
                Text("+\(filesChanged.count - 5) more")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var failedStepsBlock: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(failedSteps) { step in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.red)
                        if let cmd = step.command {
                            Text("$ \(cmd)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        if let out = step.output {
                            Text(out.prefix(200))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.red.opacity(0.8))
                                .lineLimit(3)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        } label: {
            Text("What failed (\(failedSteps.count))")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.red)
        }
    }

    private var nextActionsBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Next")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.tertiary)
            if let handoff = handoffGoalPreview {
                Button {
                    onContinue?()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.forward")
                            .font(.system(size: 9))
                        Text("Continue: \(handoff.prefix(50))")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .tint(.accentColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(nextActions) { action in
                    Button {
                        onNextAction?(action)
                    } label: {
                        HStack(spacing: 4) {
                            Text(action.label)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Text(String(format: "%.0f%%", action.confidence * 100))
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help(action.prompt)
                }
            }
        }
    }

    private var memoriesPopover: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Memories used (\(session.memoryKeysUsed.count))", systemImage: "brain.head.profile")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.purple)
            Divider()
            ForEach(Array(session.memoryKeysUsed.prefix(20).enumerated()), id: \.offset) { _, key in
                HStack(spacing: 4) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 4))
                        .foregroundStyle(.tertiary)
                    Text(key)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            if session.memoryKeysUsed.count > 20 {
                Text("+\(session.memoryKeysUsed.count - 20) more")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .frame(minWidth: 240, maxWidth: 340)
    }

    // MARK: - Summary derivations

    private var filesChanged: [String] {
        session.result?.filesChanged ?? []
    }

    private var failedSteps: [AgentPlanStep] {
        (session.plan?.steps ?? []).filter { $0.status == .failed }
    }

    private var nextActions: [NextAction] {
        session.result?.nextActions ?? []
    }

    private var exitHeadline: String {
        guard let result = session.result else {
            return session.phase == .failed ? "Failed" : "Done"
        }
        let seconds = result.durationMs / 1000
        let durationText = seconds < 60 ? "\(seconds)s" : "\(seconds / 60)m \(seconds % 60)s"
        let fileText = result.filesChanged.isEmpty
            ? ""
            : " · \(result.filesChanged.count) file\(result.filesChanged.count == 1 ? "" : "s") changed"
        switch result.exitStatus {
        case .succeeded: return "Completed · \(durationText)\(fileText)"
        case .failed:    return "Failed · \(durationText)\(fileText)"
        case .partial:   return "Partial · \(durationText)\(fileText)"
        case .cancelled: return "Cancelled · \(durationText)"
        }
    }

    private var exitIcon: String {
        guard let result = session.result else { return "checkmark.circle.fill" }
        switch result.exitStatus {
        case .succeeded: return "checkmark.circle.fill"
        case .failed:    return "exclamationmark.triangle.fill"
        case .partial:   return "exclamationmark.circle.fill"
        case .cancelled: return "xmark.circle.fill"
        }
    }

    private var exitTint: Color {
        guard let result = session.result else { return .green }
        switch result.exitStatus {
        case .succeeded: return .green
        case .failed:    return .red
        case .partial:   return .orange
        case .cancelled: return .secondary
        }
    }

    // MARK: - Browser research block

    private func browserResearchBlock(_ research: BrowserResearchSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            BrowserResearchProgressStrip(session: research)
            ForEach(research.findings) { finding in
                BrowserFindingCard(
                    url: finding.url,
                    title: finding.title,
                    preview: finding.preview,
                    fullContent: finding.content,
                    isKept: session.keptFindingIDs.contains(finding.id),
                    onSave: {
                        onSaveFinding?(finding)
                    }
                )
            }
            if research.isComplete,
               !research.findings.isEmpty,
               !research.findings.allSatisfy({ session.keptFindingIDs.contains($0.id) }) {
                HStack {
                    Spacer()
                    Button {
                        onSaveAllFindings?()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 9))
                            Text("Save all findings to memory").font(.system(size: 10, weight: .medium, design: .rounded))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .tint(.teal)
                }
            }
        }
    }

    // MARK: - Buttons

    private var buttonsRow: some View {
        HStack(spacing: 8) {
            Spacer()
            switch session.phase {
            case .awaitingApproval:
                Button("Deny") { onDeny() }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                if hasSafeSteps, let onApproveSafe {
                    Button("Approve Safe") { onApproveSafe() }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                }
                Button("Approve All") { onApprove() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                    .tint(.orange)
            case .completed, .failed, .cancelled:
                Button("Dismiss") { onDismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            case .idle, .thinking, .running, .summarizing:
                Button {
                    onStop()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.fill").font(.system(size: 9))
                        Text("Stop").font(.system(size: 10, weight: .medium, design: .rounded))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(.red)
            }
        }
    }
}

private struct InlineAgentTranscriptRow: View {
    let step: InlineAgentStep

    private var tint: Color {
        switch step.kind {
        case .goal: return .purple
        case .plan: return .blue
        case .command: return .primary
        case .observation: return .secondary
        case .summary: return .green
        case .error: return .red
        }
    }

    private var surfaceFill: Color {
        switch step.kind {
        case .command:
            return Color.accentColor.opacity(0.08)
        case .observation:
            return Color.black.opacity(0.18)
        case .summary:
            return Color.green.opacity(0.08)
        case .error:
            return Color.red.opacity(0.08)
        case .goal, .plan:
            return Color.white.opacity(0.04)
        }
    }

    private var displayText: String {
        if let command = step.command, !command.isEmpty {
            return step.kind == .command ? "$ \(command)" : command
        }
        return step.text
    }

    private var displayFont: Font {
        switch step.kind {
        case .command, .observation:
            return .system(size: 11, design: .monospaced)
        case .goal:
            return .system(size: 11, weight: .medium, design: .rounded)
        case .plan, .summary, .error:
            return .system(size: 11, design: .rounded)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(step.kind.title)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Text(step.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 0)
            }

            Text(displayText)
                .font(displayFont)
                .foregroundStyle(step.kind == .error ? .red : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(9)
        .background(surfaceFill, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(tint.opacity(0.12), lineWidth: 1)
        )
    }
}
