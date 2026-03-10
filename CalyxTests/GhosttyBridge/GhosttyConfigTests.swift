// GhosttyConfigTests.swift
// CalyxTests
//
// Tests for GhosttyConfigManager preset template and migration helpers.
// Verifies cursor-click-to-move is removed from preset and existing configs.

import Testing
@testable import Calyx

@MainActor
@Suite("GhosttyConfig Tests")
struct GhosttyConfigTests {

    // MARK: - Preset Template Tests

    @Test("Glass preset template does not contain cursor-click-to-move")
    func glassPresetTemplateDoesNotContainCursorClickToMove() {
        let template = GhosttyConfigManager.glassPresetTemplate
        #expect(!template.contains("cursor-click-to-move"),
                "Glass preset template should not contain cursor-click-to-move (ghostty default is used)")
    }

    // MARK: - Migration Tests

    @Test("removeCursorClickToMoveLine removes 'cursor-click-to-move = true'")
    func removeCursorClickToMoveLineRemovesTrue() {
        let input = """
        # --- Calyx Glass Preset (managed) ---
        background-opacity = 0.82
        cursor-click-to-move = true
        # --- End Calyx Glass Preset ---
        """
        let result = GhosttyConfigManager.removeCursorClickToMoveLine(from: input)
        #expect(!result.contains("cursor-click-to-move"))
        #expect(result.contains("background-opacity = 0.82"))
        #expect(result.contains("# --- Calyx Glass Preset (managed) ---"))
        #expect(result.contains("# --- End Calyx Glass Preset ---"))
    }

    @Test("removeCursorClickToMoveLine removes 'cursor-click-to-move = false'")
    func removeCursorClickToMoveLineRemovesFalse() {
        let input = """
        # --- Calyx Glass Preset (managed) ---
        background-opacity = 0.82
        cursor-click-to-move = false
        # --- End Calyx Glass Preset ---
        """
        let result = GhosttyConfigManager.removeCursorClickToMoveLine(from: input)
        #expect(!result.contains("cursor-click-to-move"))
        #expect(result.contains("background-opacity = 0.82"))
    }

    @Test("removeCursorClickToMoveLine is no-op when line is absent")
    func removeCursorClickToMoveLineNoOpWhenAbsent() {
        let input = """
        # --- Calyx Glass Preset (managed) ---
        background-opacity = 0.82
        # --- End Calyx Glass Preset ---
        """
        let result = GhosttyConfigManager.removeCursorClickToMoveLine(from: input)
        #expect(result == input)
    }

    @Test("removeCursorClickToMoveLine handles extra whitespace")
    func removeCursorClickToMoveLineHandlesExtraWhitespace() {
        let input = "  cursor-click-to-move = true  \nbackground-opacity = 0.82\n"
        let result = GhosttyConfigManager.removeCursorClickToMoveLine(from: input)
        #expect(!result.contains("cursor-click-to-move"))
        #expect(result.contains("background-opacity = 0.82"))
    }
}
