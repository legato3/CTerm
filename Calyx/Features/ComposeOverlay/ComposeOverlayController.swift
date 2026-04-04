// ComposeOverlayController.swift
// Calyx
//
// Manages the compose overlay lifecycle: tracks which surface is targeted,
// handles show/hide state, dispatches text to the terminal, and coordinates
// Warp-style assistant interactions.

import AppKit
import GhosttyKit
import OSLog

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.legato3.terminal",
    category: "ComposeOverlayController"
)

@MainActor
final class ComposeOverlayController {
    let assistantState = ComposeAssistantState()

    /// The surface ID that will receive composed text.
    /// Set when the overlay opens; cleared when it closes.
    private(set) var targetSurfaceID: UUID?

    /// When `true`, the composed text is sent to every pane in the active tab's split tree
    /// instead of only the targeted surface.
    var broadcastEnabled: Bool = false

    // MARK: - Overlay Lifecycle

    func toggle(
        windowSession: WindowSession,
        focusedControllerID: UUID?
    ) {
        if windowSession.showComposeOverlay {
            dismiss(windowSession: windowSession, onDismiss: nil)
        } else {
            guard let activeTab = windowSession.activeGroup?.activeTab,
                  case .terminal = activeTab.content else { return }
            targetSurfaceID = focusedControllerID
            windowSession.showComposeOverlay = true
        }
    }

    func retargetIfNeeded(windowSession: WindowSession, focusedControllerID: UUID?) {
        guard windowSession.showComposeOverlay else { return }
        targetSurfaceID = focusedControllerID
    }

    func dismiss(windowSession: WindowSession, onDismiss: (() -> Void)?) {
        guard windowSession.showComposeOverlay else { return }
        windowSession.showComposeOverlay = false
        targetSurfaceID = nil
        onDismiss?()
    }

    // MARK: - Text Dispatch

    func send(
        _ text: String,
        activeTab: Tab?,
        focusedController: GhosttySurfaceController?,
        sendEnterKey: @escaping (GhosttySurfaceController) -> Void
    ) -> Bool {
        let raw = text
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        switch assistantState.mode {
        case .shell:
            return dispatchShellCommand(
                raw,
                entryID: nil,
                activeTab: activeTab,
                focusedController: focusedController,
                sendEnterKey: sendEnterKey
            )
        case .ollamaCommand:
            return generateSuggestion(
                from: trimmed,
                activeTab: activeTab
            )
        }
    }

    func applyAssistantEntry(
        id: UUID,
        run: Bool,
        activeTab: Tab?,
        focusedController: GhosttySurfaceController?,
        sendEnterKey: @escaping (GhosttySurfaceController) -> Void
    ) -> Bool {
        guard let entry = assistantState.entry(id: id),
              let command = entry.runnableCommand
        else { return false }

        if run {
            return dispatchShellCommand(
                command,
                entryID: id,
                activeTab: activeTab,
                focusedController: focusedController,
                sendEnterKey: sendEnterKey
            )
        }

        return assistantState.loadDraft(from: id)
    }

    func explainEntry(
        id: UUID,
        activeTab: Tab?,
        focusedController: GhosttySurfaceController?
    ) {
        guard let sourceEntry = assistantState.entry(id: id) else { return }
        guard let output = resolveContextSnippet(for: sourceEntry, activeTab: activeTab, focusedController: focusedController) else {
            let explainID = assistantState.beginEntry(kind: .explanation, prompt: sourceEntry.prompt)
            assistantState.failEntry(id: explainID, message: "No recent terminal output was available to explain.")
            return
        }

        let explainID = assistantState.beginEntry(
            kind: .explanation,
            prompt: sourceEntry.runnableCommand ?? sourceEntry.prompt,
            contextSnippet: output
        )
        let pwd = activeTab?.pwd
        let command = sourceEntry.runnableCommand

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let response = try await OllamaCommandService.explainCommandOutput(command: command, output: output, pwd: pwd)
                self.assistantState.finishEntry(id: explainID, response: response, contextSnippet: output)
            } catch {
                self.assistantState.failEntry(id: explainID, message: error.localizedDescription, contextSnippet: output)
            }
        }
    }

    func fixEntry(
        id: UUID,
        activeTab: Tab?,
        focusedController: GhosttySurfaceController?
    ) {
        guard let sourceEntry = assistantState.entry(id: id) else { return }
        guard let output = resolveContextSnippet(for: sourceEntry, activeTab: activeTab, focusedController: focusedController) else {
            let fixID = assistantState.beginEntry(kind: .fixSuggestion, prompt: sourceEntry.prompt)
            assistantState.failEntry(id: fixID, message: "No recent terminal output was available to fix.")
            return
        }

        let fixID = assistantState.beginEntry(
            kind: .fixSuggestion,
            prompt: sourceEntry.runnableCommand ?? sourceEntry.prompt,
            contextSnippet: output
        )
        let pwd = activeTab?.pwd
        let command = sourceEntry.runnableCommand

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let response = try await OllamaCommandService.suggestFix(command: command, output: output, pwd: pwd)
                self.assistantState.finishEntry(id: fixID, response: response, command: response, contextSnippet: output)
            } catch {
                self.assistantState.failEntry(id: fixID, message: error.localizedDescription, contextSnippet: output)
            }
        }
    }

    // MARK: - Internals

    private func generateSuggestion(from prompt: String, activeTab: Tab?) -> Bool {
        let entryID = assistantState.beginEntry(kind: .commandSuggestion, prompt: prompt)
        let pwd = activeTab?.pwd

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let response = try await OllamaCommandService.generateCommand(for: prompt, pwd: pwd)
                self.assistantState.finishEntry(id: entryID, response: response, command: response)
            } catch {
                self.assistantState.failEntry(id: entryID, message: error.localizedDescription)
            }
        }
        return true
    }

    private func dispatchShellCommand(
        _ text: String,
        entryID: UUID?,
        activeTab: Tab?,
        focusedController: GhosttySurfaceController?,
        sendEnterKey: @escaping (GhosttySurfaceController) -> Void
    ) -> Bool {
        guard let controller = resolveTargetController(activeTab: activeTab, focusedController: focusedController) else {
            return false
        }

        let commandText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveEntryID: UUID
        if let entryID {
            effectiveEntryID = entryID
            assistantState.markRan(id: entryID)
        } else {
            effectiveEntryID = assistantState.addEntry(
                kind: .shellDispatch,
                prompt: commandText,
                command: commandText,
                status: .ran
            )
        }

        if let tab = activeTab, tab.isAIAgentTab {
            AgentTextRouter.submit(text, to: controller, inputStyle: tab.preferredAgentInputStyle, sendEnterKey: sendEnterKey)
        } else {
            controller.sendText(text)
            sendEnterKey(controller)
        }

        if broadcastEnabled, let tab = activeTab {
            for leafID in tab.splitTree.allLeafIDs() {
                guard let otherController = tab.registry.controller(for: leafID),
                      otherController.id != controller.id else { continue }
                otherController.sendText(text)
                sendEnterKey(otherController)
            }
        }

        assistantState.setDraftText("")
        scheduleContextRefresh(for: effectiveEntryID, activeTab: activeTab, focusedController: focusedController)
        logger.debug("Sent compose text (\(text.count) chars) to surface \(String(describing: self.targetSurfaceID))\(self.broadcastEnabled ? " [broadcast]" : "")")
        return true
    }

    private func scheduleContextRefresh(
        for entryID: UUID,
        activeTab: Tab?,
        focusedController: GhosttySurfaceController?
    ) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard let self else { return }
            guard let entry = self.assistantState.entry(id: entryID) else { return }
            if let snippet = self.resolveContextSnippet(for: entry, activeTab: activeTab, focusedController: focusedController) {
                self.assistantState.attachContext(snippet, to: entryID)
            }
        }
    }

    private func resolveContextSnippet(
        for entry: ComposeAssistantEntry,
        activeTab: Tab?,
        focusedController: GhosttySurfaceController?
    ) -> String? {
        if let shellError = activeTab?.lastShellError?.snippet,
           !shellError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return shellError
        }

        if let contextSnippet = entry.contextSnippet,
           !contextSnippet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return contextSnippet
        }

        return readViewportSnippet(activeTab: activeTab, focusedController: focusedController)
    }

    private func readViewportSnippet(
        activeTab: Tab?,
        focusedController: GhosttySurfaceController?
    ) -> String? {
        guard let controller = resolveTargetController(activeTab: activeTab, focusedController: focusedController),
              let surface = controller.surface,
              let text = GhosttyFFI.surfaceReadViewportText(surface)
        else { return nil }

        let lines = text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let snippet = lines.suffix(24).joined(separator: "\n")
        return snippet.isEmpty ? nil : snippet
    }

    private func resolveTargetController(
        activeTab: Tab?,
        focusedController: GhosttySurfaceController?
    ) -> GhosttySurfaceController? {
        if let targetID = targetSurfaceID,
           let tab = activeTab,
           let controller = tab.registry.controller(for: targetID) {
            return controller
        }

        if let focusedController {
            return focusedController
        }

        guard let tab = activeTab else { return nil }
        if let focusedLeaf = tab.splitTree.focusedLeafID,
           let controller = tab.registry.controller(for: focusedLeaf) {
            return controller
        }
        return tab.splitTree.allLeafIDs().compactMap { tab.registry.controller(for: $0) }.first
    }
}
