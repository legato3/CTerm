// SidebarUITests.swift
// CTermUITests

import XCTest

final class SidebarUITests: CTermUITestCase {

    func test_sidebarVisibleByDefault() {
        let sidebar = app.descendants(matching: .any)
            .matching(identifier: "cterm.sidebar")
            .firstMatch
        XCTAssertTrue(waitFor(sidebar), "Sidebar should be visible by default")
    }

    func test_toggleSidebar_hidesAndShows() {
        let sidebar = app.descendants(matching: .any)
            .matching(identifier: "cterm.sidebar")
            .firstMatch
        XCTAssertTrue(waitFor(sidebar), "Sidebar should initially be visible")

        // Hide sidebar
        toggleSidebarViaMenu()
        waitForNonExistence(sidebar)

        // Show sidebar
        toggleSidebarViaMenu()
        XCTAssertTrue(waitFor(sidebar), "Sidebar should be visible again after toggle")
    }

    func test_sidebarShowsTab() {
        let tabCount = countElements(matching: "cterm.sidebar.tab.", excludingSuffix: ".closeButton")
        XCTAssertEqual(tabCount, 1, "Should have one tab in sidebar initially")
    }
}
