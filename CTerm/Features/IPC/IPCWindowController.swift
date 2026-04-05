import AppKit
import GhosttyKit
import OSLog

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.legato3.cterm",
    category: "IPCWindowController"
)

/// Handles IPC enable/disable lifecycle and IPC-triggered window actions
/// (workflow launch, review dispatch). Owned by CTermWindowController.
@MainActor
final class IPCWindowController {
    private let mcpServer: CTermMCPServer
    private weak var windowSession: WindowSession?

    /// Called to open a new terminal tab with the given working directory.
    var onCreateNewTab: ((String?) -> Void)?
    /// Called to switch focus to a specific tab by ID.
    var onSwitchToTab: ((UUID) -> Void)?
    /// Called to send a Return/Enter key to a terminal surface controller.
    var onSendEnterKey: ((GhosttySurfaceController) -> Void)?
    /// Returns the active tab's current working directory (for workflow directory defaulting).
    var getActiveTabPwd: (() -> String?)?
    /// Called when IPC review is requested — should open the git sidebar.
    var onShowGitSidebar: (() -> Void)?

    /// Pending role prompts keyed by tab title (role name). Populated during workflow launch;
    /// consumed when the matching peer calls register_peer.
    private var pendingRolePrompts: [String: (tab: Tab, prompt: String)] = [:]
    /// Notification observer token for peerRegistered events. Using NSObjectProtocol boxed
    /// in a class wrapper so the block-based observer is removed when no longer needed.
    private var peerRegisteredObserver: NSObjectProtocol?
    /// Test hook to stub runtime launch without a real terminal surface.
    var launchRuntimeCommandOverride: ((Tab, String) -> Bool)?
    /// Test hook to stub prompt delivery without a real terminal surface.
    var deliverRolePromptOverride: ((Tab, String, AgentInputStyle) -> Bool)?

    init(mcpServer: CTermMCPServer, windowSession: WindowSession) {
        self.mcpServer = mcpServer
        self.windowSession = windowSession
    }


    // MARK: - IPC Toggle

    func enableIPC() {
        do {
            let token = SecurityUtils.generateHexToken()
            try mcpServer.start(token: token)
            let port = mcpServer.port
            let result = IPCConfigManager.enableIPC(port: port, token: token)

            if !result.anySucceeded {
                mcpServer.stop()
                showAlert(
                    title: "IPC Error",
                    message: "MCP server running on port \(port).\nNo agent configs found. Configure manually if needed."
                )
                return
            }

            UserDefaults.standard.set(true, forKey: "cterm.ipcAutoStart")
            IPCAgentState.shared.startPolling()
            showAlert(
                title: "IPC Enabled",
                message: "MCP server running on port \(port).\n\(configStatusMessage(result))\nRestart agent instances to connect."
            )
        } catch {
            showAlert(title: "IPC Error", message: error.localizedDescription)
        }
    }

    func disableIPC() {
        UserDefaults.standard.set(false, forKey: "cterm.ipcAutoStart")
        mcpServer.stop()
        IPCAgentState.shared.stopPolling()
        IPCAgentState.shared.clearLog()
        let result = IPCConfigManager.disableIPC()
        showAlert(
            title: "IPC Disabled",
            message: "MCP server stopped.\n\(configStatusMessage(result))"
        )
    }

    // MARK: - Review Requested

    func handleReviewRequested() {
        guard let session = windowSession else { return }
        session.sidebarMode = .changes
        session.showSidebar = true
        onShowGitSidebar?()
    }

    // MARK: - Workflow Launch

    func handleLaunchWorkflow(event: CTermIPCLaunchWorkflowEvent) {
        let roleNames = event.roleNames
        let autoStart = event.autoStart
        let sessionName = event.sessionName
        let initialTask = event.initialTask
        let runtime = event.runtime
        let port = mcpServer.port

        let pwd: String
        if event.skipDirectoryPrompt,
           let preferredDirectory = resolvedLaunchDirectory(for: event) {
            pwd = preferredDirectory
        } else {
            let panel = NSOpenPanel()
            panel.title = "Choose Session Directory"
            panel.message = "All agent tabs will open in this folder."
            panel.prompt = "Open"
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false

            if let tabPwd = getActiveTabPwd?() {
                panel.directoryURL = URL(fileURLWithPath: tabPwd)
            }

            guard panel.runModal() == .OK, let chosenURL = panel.url else { return }
            pwd = chosenURL.path
        }

        IPCAgentState.shared.lastWorkflow = roleNames

        if !sessionName.isEmpty {
            windowSession?.activeGroup?.name = sessionName
        }

        var createdTabs: [Tab] = []
        for roleName in roleNames {
            onCreateNewTab?(pwd)
            if let newTab = windowSession?.activeGroup?.tabs.last {
                newTab.title = roleName
                newTab.agentRuntime = runtime.preset
                newTab.agentInputStyle = runtime.inputStyle
                createdTabs.append(newTab)
            }
        }

        guard autoStart, createdTabs.count == roleNames.count else { return }

        if runtime.registersWithIPC {
            // Build a role-name → (tab, prompt) map so we can inject prompts after the
            // runtime launches, with peerRegistered kept as a retry path if startup races.
            for (tab, roleName) in zip(createdTabs, roleNames) {
                let prompt = AgentWorkflow.rolePrompt(
                    roleName: roleName,
                    allRoles: roleNames,
                    runtime: runtime,
                    port: port,
                    initialTask: initialTask
                )
                pendingRolePrompts[roleName.lowercased()] = (tab: tab, prompt: prompt)
            }

            // Subscribe to peerRegistered once (idempotent — remove any previous observer first).
            if let existing = peerRegisteredObserver {
                NotificationCenter.default.removeObserver(existing)
            }
            peerRegisteredObserver = NotificationCenter.default.addObserver(
                forName: .peerRegistered,
                object: nil,
                queue: .main
            ) { [weak self] note in
                // Extract Sendable values from the Notification before crossing into the Task.
                let peerName = note.userInfo?["name"] as? String
                Task { @MainActor [weak self] in
                    self?.handlePeerRegisteredNamed(peerName)
                }
            }
        }

        // Launch the selected runtime in each tab after a short shell-ready delay.
        for (index, (tab, roleName)) in zip(createdTabs, roleNames).enumerated() {
            let baseDelay = Double(index) * 0.15
            DispatchQueue.main.asyncAfter(deadline: .now() + baseDelay + 0.8) { [weak self] in
                guard let self else { return }
                guard !runtime.launchCommand.isEmpty else { return }
                guard self.launchRuntime(command: runtime.launchCommand, in: tab) else { return }

                if runtime.registersWithIPC {
                    self.schedulePendingRolePromptInjection(for: roleName, after: 2.0)
                    return
                }

                let prompt = AgentWorkflow.rolePrompt(
                    roleName: tab.title,
                    allRoles: roleNames,
                    runtime: runtime,
                    port: port,
                    initialTask: initialTask
                )

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    guard let self else { return }
                    _ = self.deliverRolePrompt(prompt, to: tab, inputStyle: runtime.inputStyle)
                }
            }
        }
    }

    private func resolvedLaunchDirectory(for event: CTermIPCLaunchWorkflowEvent) -> String? {
        if let workingDirectory = event.workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines),
           !workingDirectory.isEmpty {
            return workingDirectory
        }

        if let activeTabPwd = getActiveTabPwd?()?.trimmingCharacters(in: .whitespacesAndNewlines),
           !activeTabPwd.isEmpty {
            return activeTabPwd
        }

        return nil
    }

    // MARK: - Peer Registration Event Handler

    /// Called when any agent calls register_peer. Looks up the matching pending role prompt
    /// by peer name (which must equal the tab title / role name) and injects it.
    private func handlePeerRegisteredNamed(_ peerName: String?) {
        guard let peerName else { return }
        let key = peerName.lowercased()

        guard pendingRolePrompts[key] != nil else {
            // Either not a workflow agent, or already handled.
            return
        }

        if injectPendingRolePrompt(named: peerName) {
            return
        }

        logger.warning("IPCWindowController: peerRegistered for '\(peerName)' before prompt delivery; retrying in 1s")
        schedulePendingRolePromptInjection(for: peerName, after: 1.0)
    }

    // MARK: - Review → Agent Dispatch

    func sendToAgent(_ payload: String) -> ReviewSendResult {
        guard let session = windowSession else { return .failed }

        let agentTabs = session.groups.flatMap(\.tabs).filter(\.isAIAgentTab)

        guard !agentTabs.isEmpty else {
            showAlert(
                title: "No AI Agent",
                message: "No terminal tabs marked as AI agents were found. Start an AI agent first."
            )
            return .failed
        }

        let targetTab: Tab
        if agentTabs.count == 1 {
            targetTab = agentTabs[0]
        } else {
            let alert = NSAlert()
            alert.messageText = "Select AI Agent Tab"
            alert.informativeText = "Choose which AI agent instance to send the review to:"
            alert.addButton(withTitle: "Send")
            alert.addButton(withTitle: "Cancel")

            let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
            for (i, tab) in agentTabs.enumerated() {
                let groupName = session.groups.first { $0.tabs.contains { $0.id == tab.id } }?.name ?? ""
                let label = "\(tab.title) — \(groupName) (#\(i + 1))"
                popup.addItem(withTitle: label)
            }
            alert.accessoryView = popup

            let response = alert.runModal()
            guard response == .alertFirstButtonReturn else { return .cancelled }

            let selectedIndex = popup.indexOfSelectedItem
            guard selectedIndex >= 0, selectedIndex < agentTabs.count else { return .failed }
            targetTab = agentTabs[selectedIndex]
        }

        guard let focusedID = targetTab.splitTree.focusedLeafID,
              let controller = targetTab.registry.controller(for: focusedID) else {
            showAlert(title: "Send Failed", message: "Could not access terminal surface.")
            return .failed
        }

        AgentTextRouter.submit(
            payload,
            to: controller,
            inputStyle: targetTab.preferredAgentInputStyle,
            sendEnterKey: { [weak self] controller in self?.onSendEnterKey?(controller) }
        )

        onSwitchToTab?(targetTab.id)
        return .sent
    }

    // MARK: - Helpers

    func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func configStatusMessage(_ result: IPCConfigResult) -> String {
        func label(_ status: ConfigStatus, name: String) -> String {
            switch status {
            case .success:
                return "\(name): configured"
            case .skipped(let reason):
                return "\(name): \(reason) (skipped)"
            case .failed(let error):
                return "\(name): error - \(error.localizedDescription)"
            }
        }
        return [
            label(result.claudeCode, name: "Claude Code"),
            label(result.codex, name: "Codex")
        ].joined(separator: "\n")
    }

    @discardableResult
    private func launchRuntime(command: String, in tab: Tab) -> Bool {
        if let launchRuntimeCommandOverride {
            return launchRuntimeCommandOverride(tab, command)
        }

        guard let leafID = tab.splitTree.focusedLeafID,
              let controller = tab.registry.controller(for: leafID) else { return false }

        controller.sendText(command)
        onSendEnterKey?(controller)
        return true
    }

    @discardableResult
    private func deliverRolePrompt(
        _ prompt: String,
        to tab: Tab,
        inputStyle: AgentInputStyle
    ) -> Bool {
        if let deliverRolePromptOverride {
            return deliverRolePromptOverride(tab, prompt, inputStyle)
        }

        guard let leafID = tab.splitTree.focusedLeafID,
              let controller = tab.registry.controller(for: leafID) else { return false }

        AgentTextRouter.submit(
            prompt,
            to: controller,
            inputStyle: inputStyle,
            sendEnterKey: { [weak self] controller in self?.onSendEnterKey?(controller) }
        )
        return true
    }

    private func schedulePendingRolePromptInjection(for roleName: String, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            _ = self?.injectPendingRolePrompt(named: roleName)
        }
    }

    @discardableResult
    private func injectPendingRolePrompt(named roleName: String) -> Bool {
        let key = roleName.lowercased()
        guard let entry = pendingRolePrompts[key] else { return false }
        guard deliverRolePrompt(entry.prompt, to: entry.tab, inputStyle: entry.tab.preferredAgentInputStyle) else {
            return false
        }

        logger.info("IPCWindowController: injecting role prompt for '\(roleName)'")
        pendingRolePrompts.removeValue(forKey: key)
        cleanupPeerRegisteredObserverIfNeeded()
        return true
    }

    private func cleanupPeerRegisteredObserverIfNeeded() {
        guard pendingRolePrompts.isEmpty, let observer = peerRegisteredObserver else { return }
        NotificationCenter.default.removeObserver(observer)
        peerRegisteredObserver = nil
    }
}
