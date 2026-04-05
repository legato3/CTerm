// SearchUITests.swift
// CTermUITests

import XCTest

final class SearchUITests: CTermUITestCase {

    private func openSearchViaCommandPalette() {
        openCommandPaletteViaMenu()
        let searchField = app.descendants(matching: .any)
            .matching(identifier: "cterm.commandPalette.searchField")
            .firstMatch
        XCTAssertTrue(waitFor(searchField))
        searchField.typeText("Find in Terminal")
        searchField.typeKey(.enter, modifierFlags: [])
    }

    func test_openSearchBar() {
        openSearchViaCommandPalette()

        // Search field should appear
        let field = app.descendants(matching: .any)
            .matching(identifier: "cterm.search.searchField")
            .firstMatch
        XCTAssertTrue(waitFor(field), "Search bar should appear")
    }

    func test_dismissSearchWithEscape() {
        openSearchViaCommandPalette()

        let field = app.descendants(matching: .any)
            .matching(identifier: "cterm.search.searchField")
            .firstMatch
        XCTAssertTrue(waitFor(field))

        // Dismiss with Escape
        app.typeKey(.escape, modifierFlags: [])

        waitForNonExistence(field)
    }

    func test_searchBarHasAllControls() {
        openSearchViaCommandPalette()

        let field = app.descendants(matching: .any)
            .matching(identifier: "cterm.search.searchField")
            .firstMatch
        XCTAssertTrue(waitFor(field))

        // Verify all controls exist
        let prevButton = app.descendants(matching: .any)
            .matching(identifier: "cterm.search.previousButton")
            .firstMatch
        XCTAssertTrue(prevButton.exists, "Previous button should exist")

        let nextButton = app.descendants(matching: .any)
            .matching(identifier: "cterm.search.nextButton")
            .firstMatch
        XCTAssertTrue(nextButton.exists, "Next button should exist")

        let closeButton = app.descendants(matching: .any)
            .matching(identifier: "cterm.search.closeButton")
            .firstMatch
        XCTAssertTrue(closeButton.exists, "Close button should exist")
    }

    func test_closeButtonDismissesSearch() {
        openSearchViaCommandPalette()

        let field = app.descendants(matching: .any)
            .matching(identifier: "cterm.search.searchField")
            .firstMatch
        XCTAssertTrue(waitFor(field))

        // Click close button
        let closeButton = app.descendants(matching: .any)
            .matching(identifier: "cterm.search.closeButton")
            .firstMatch
        XCTAssertTrue(closeButton.exists)
        closeButton.click()

        waitForNonExistence(field)
    }
}
