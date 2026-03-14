// BrowserScriptingUITests.swift
// CalyxUITests
//
// E2E tests for browser scripting enable/disable via command palette.

import XCTest

final class BrowserScriptingUITests: CalyxUITestCase {

    private func openCommandPalette() {
        openCommandPaletteViaMenu()
        let searchField = app.descendants(matching: .any)
            .matching(identifier: "calyx.commandPalette.searchField")
            .firstMatch
        XCTAssertTrue(waitFor(searchField), "Command palette should appear")
    }

    private func paletteSearchField() -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "calyx.commandPalette.searchField")
            .firstMatch
    }

    private func resultsTable() -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "calyx.commandPalette.resultsTable")
            .firstMatch
    }

    func test_enableBrowserScripting() {
        openCommandPalette()

        let sf = paletteSearchField()
        sf.typeText("Browser Scripting")
        Thread.sleep(forTimeInterval: 0.5)

        let rt = resultsTable()
        XCTAssertTrue(rt.exists)
        XCTAssertGreaterThan(rt.tableRows.count, 0, "Should find Browser Scripting command")

        // Execute (first result should be "Enable Browser Scripting (Unsafe)")
        sf.typeKey(.enter, modifierFlags: [])

        // Warning dialog
        let dialog = app.dialogs.firstMatch
        XCTAssertTrue(dialog.waitForExistence(timeout: 5), "Warning dialog should appear")
        dialog.buttons["Enable"].click()

        // Verify "Disable" now appears
        Thread.sleep(forTimeInterval: 0.5)
        openCommandPalette()
        paletteSearchField().typeText("Disable Browser")
        Thread.sleep(forTimeInterval: 0.5)

        XCTAssertGreaterThan(resultsTable().tableRows.count, 0, "Disable command should appear after enabling")
        app.typeKey(.escape, modifierFlags: [])
    }

    func test_disableBrowserScripting() {
        // Enable first
        openCommandPalette()
        paletteSearchField().typeText("Browser Scripting")
        Thread.sleep(forTimeInterval: 0.5)
        paletteSearchField().typeKey(.enter, modifierFlags: [])

        let enableDialog = app.dialogs.firstMatch
        if enableDialog.waitForExistence(timeout: 5) {
            enableDialog.buttons["Enable"].click()
        }
        Thread.sleep(forTimeInterval: 0.5)

        // Now disable
        openCommandPalette()
        paletteSearchField().typeText("Disable Browser")
        Thread.sleep(forTimeInterval: 0.5)
        paletteSearchField().typeKey(.enter, modifierFlags: [])

        let disableDialog = app.dialogs.firstMatch
        XCTAssertTrue(disableDialog.waitForExistence(timeout: 5), "Disable dialog should appear")
        disableDialog.buttons["OK"].click()

        // Verify "Enable" is back
        Thread.sleep(forTimeInterval: 0.5)
        openCommandPalette()
        paletteSearchField().typeText("Enable Browser")
        Thread.sleep(forTimeInterval: 0.5)

        XCTAssertGreaterThan(resultsTable().tableRows.count, 0, "Enable command should reappear")
        app.typeKey(.escape, modifierFlags: [])
    }

    func test_browserTabWithScriptingEnabled() {
        // Enable scripting
        openCommandPalette()
        paletteSearchField().typeText("Browser Scripting")
        Thread.sleep(forTimeInterval: 0.5)
        paletteSearchField().typeKey(.enter, modifierFlags: [])

        let dialog = app.dialogs.firstMatch
        if dialog.waitForExistence(timeout: 5) {
            dialog.buttons["Enable"].click()
        }
        Thread.sleep(forTimeInterval: 0.5)

        // Open browser tab
        menuAction("File", item: "New Browser Tab")
        let urlDialog = app.dialogs.firstMatch
        XCTAssertTrue(urlDialog.waitForExistence(timeout: 5))

        let textField = urlDialog.textFields.firstMatch
        if textField.waitForExistence(timeout: 2) {
            textField.click()
            textField.typeText("https://example.com")
        }
        urlDialog.buttons["Open"].click()

        // Verify browser toolbar
        let toolbar = app.descendants(matching: .any)
            .matching(identifier: "calyx.browser.toolbar")
            .firstMatch
        XCTAssertTrue(waitFor(toolbar, timeout: 15), "Browser toolbar should appear")
    }

    func test_enableIPCShowsDialog() {
        openCommandPalette()
        paletteSearchField().typeText("AI Agent IPC")
        Thread.sleep(forTimeInterval: 0.5)
        paletteSearchField().typeKey(.enter, modifierFlags: [])

        let dialog = app.dialogs.firstMatch
        XCTAssertTrue(dialog.waitForExistence(timeout: 5), "IPC dialog should appear")
        dialog.buttons["OK"].click()
    }
}
