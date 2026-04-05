import Foundation
import Testing
@testable import CTerm

@MainActor
@Suite("Compose Assistant State")
struct ComposeAssistantStateTests {
    private let keys = [
        AppStorageKeys.composeAssistantMode,
        AppStorageKeys.composeModeLocked,
        AppStorageKeys.composeLastAgentMode,
        AppStorageKeys.hasSeenAgentAutoRouteHint,
    ]

    init() {
        resetDefaults()
    }

    @Test("Auto-detect keeps shell commands in shell and reuses the last agent backend for prompts")
    func effectiveModeUsesLastAgentBackend() {
        defer { resetDefaults() }

        let state = ComposeAssistantState()
        #expect(state.mode == .shell)
        #expect(state.isModeLocked == false)

        state.mode = .ollamaAgent
        #expect(state.lastAgentMode == .ollamaAgent)

        state.mode = .shell
        state.isModeLocked = false

        #expect(state.effectiveMode(for: "git status") == .shell)
        #expect(state.effectiveMode(for: "fix the failing tests") == .ollamaAgent)
    }

    private func resetDefaults() {
        let defaults = UserDefaults.standard
        for key in keys {
            defaults.removeObject(forKey: key)
        }
    }
}
