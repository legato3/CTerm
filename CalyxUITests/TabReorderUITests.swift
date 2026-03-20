// TabReorderUITests.swift
// CalyxUITests
//
// UI tests for tab drag-reorder in both the tab bar and sidebar.

import XCTest

final class TabReorderUITests: CalyxUITestCase {

    // MARK: - Helpers

    /// Returns all elements whose `accessibilityValue` matches the given string.
    private func elements(withValue value: String) -> XCUIElementQuery {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "value == %@", value))
    }

    /// Returns elements whose `accessibilityValue` matches a LIKE pattern (supports `*` wildcards).
    private func elements(valueLike pattern: String) -> XCUIElementQuery {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "value LIKE %@", pattern))
    }

    /// Reads the `accessibilityIdentifier` of the element at a given tab-bar index.
    /// Returns nil if no element with that index value exists.
    private func tabBarTabIdentifier(atIndex index: Int) -> String? {
        let value = "calyx.tabBar.tab.index.\(index)"
        let query = elements(withValue: value)
        guard query.count > 0 else { return nil }
        return query.firstMatch.identifier
    }

    /// Reads the `accessibilityIdentifier` of the sidebar tab element at a given index.
    /// The value pattern is "calyx.sidebar.group.<UUID>.tab.index.<N>".
    private func sidebarTabIdentifier(atIndex index: Int) -> String? {
        let pattern = "calyx.sidebar.group.*.tab.index.\(index)"
        let query = elements(valueLike: pattern)
        guard query.count > 0 else { return nil }
        return query.firstMatch.identifier
    }

    /// Creates `count` additional tabs (beyond the initial one) and waits for them to appear.
    private func createTabs(count: Int) {
        for _ in 0..<count {
            createNewTabViaMenu()
            Thread.sleep(forTimeInterval: 1.0)
        }
    }

    // MARK: - Tab Bar Reorder

    func test_dragTabBarTab_reordersCorrectly() {
        // Arrange: create 3 tabs total (1 initial + 2 new)
        createTabs(count: 2)
        XCTAssertEqual(countTabBarTabs(), 3, "Should have 3 tabs before drag")

        // Capture the identifier of the tab currently at index 0
        let firstTabValue = "calyx.tabBar.tab.index.0"
        let firstTabElement = elements(withValue: firstTabValue).firstMatch
        XCTAssertTrue(
            waitFor(firstTabElement, timeout: 5),
            "Tab at index 0 should exist"
        )
        let originalFirstTabID = firstTabElement.identifier

        // Also capture the tab at index 2 to know the drag target position
        let thirdTabValue = "calyx.tabBar.tab.index.2"
        let thirdTabElement = elements(withValue: thirdTabValue).firstMatch
        XCTAssertTrue(
            waitFor(thirdTabElement, timeout: 5),
            "Tab at index 2 should exist"
        )

        // Act: drag the first tab to the right, past the third tab
        firstTabElement.press(forDuration: 0.2, thenDragTo: thirdTabElement)

        // Allow the reorder animation to settle
        Thread.sleep(forTimeInterval: 1.0)

        // Assert: the tab that was originally first should no longer be at index 0
        let newFirstTabID = tabBarTabIdentifier(atIndex: 0)
        XCTAssertNotNil(newFirstTabID, "A tab should exist at index 0 after reorder")
        XCTAssertNotEqual(
            newFirstTabID, originalFirstTabID,
            "After dragging the first tab past the third, a different tab should now occupy index 0"
        )

        // The original first tab should now be at index 1 or 2
        let tabAtIndex1 = tabBarTabIdentifier(atIndex: 1)
        let tabAtIndex2 = tabBarTabIdentifier(atIndex: 2)
        let originalTabMoved = (tabAtIndex1 == originalFirstTabID) || (tabAtIndex2 == originalFirstTabID)
        XCTAssertTrue(
            originalTabMoved,
            "The original first tab should have moved to index 1 or 2"
        )
    }

    // MARK: - Sidebar Reorder

    func test_dragSidebarTab_reordersCorrectly() {
        // Arrange: create 3 tabs total
        createTabs(count: 2)
        XCTAssertEqual(countTabBarTabs(), 3, "Should have 3 tabs before toggling sidebar")

        // Open the sidebar
        toggleSidebarViaMenu()
        Thread.sleep(forTimeInterval: 1.0)

        // Find the sidebar tab at index 0
        let firstSidebarPattern = "calyx.sidebar.group.*.tab.index.0"
        let firstSidebarTab = elements(valueLike: firstSidebarPattern).firstMatch
        XCTAssertTrue(
            waitFor(firstSidebarTab, timeout: 5),
            "Sidebar tab at index 0 should exist"
        )
        let originalFirstSidebarID = firstSidebarTab.identifier

        // Find the sidebar tab at index 2
        let thirdSidebarPattern = "calyx.sidebar.group.*.tab.index.2"
        let thirdSidebarTab = elements(valueLike: thirdSidebarPattern).firstMatch
        XCTAssertTrue(
            waitFor(thirdSidebarTab, timeout: 5),
            "Sidebar tab at index 2 should exist"
        )

        // Act: drag the first sidebar tab down past the third
        firstSidebarTab.press(forDuration: 0.2, thenDragTo: thirdSidebarTab)

        // Allow the reorder animation to settle
        Thread.sleep(forTimeInterval: 1.0)

        // Assert: the tab that was originally at index 0 should no longer be there
        let newFirstSidebarID = sidebarTabIdentifier(atIndex: 0)
        XCTAssertNotNil(newFirstSidebarID, "A sidebar tab should exist at index 0 after reorder")
        XCTAssertNotEqual(
            newFirstSidebarID, originalFirstSidebarID,
            "After dragging the first sidebar tab past the third, a different tab should now occupy index 0"
        )

        // The original first tab should now be at a later index
        let sidebarTabAt1 = sidebarTabIdentifier(atIndex: 1)
        let sidebarTabAt2 = sidebarTabIdentifier(atIndex: 2)
        let originalSidebarTabMoved = (sidebarTabAt1 == originalFirstSidebarID) || (sidebarTabAt2 == originalFirstSidebarID)
        XCTAssertTrue(
            originalSidebarTabMoved,
            "The original first sidebar tab should have moved to index 1 or 2"
        )
    }

    // MARK: - Tap After Drag

    func test_tapStillWorksAfterDrag() {
        // Arrange: create 2 tabs total
        createTabs(count: 1)
        XCTAssertEqual(countTabBarTabs(), 2, "Should have 2 tabs")

        // Find the tab at index 0
        let firstTabValue = "calyx.tabBar.tab.index.0"
        let firstTabElement = elements(withValue: firstTabValue).firstMatch
        XCTAssertTrue(
            waitFor(firstTabElement, timeout: 5),
            "Tab at index 0 should exist"
        )
        let tabID = firstTabElement.identifier

        // Act: perform a very short press-and-drag (within the 5pt minimumDistance threshold)
        // This should not trigger a reorder; instead the tab should remain tappable.
        // We drag to a nearby coordinate offset (2pt right, 0pt down) which is < minimumDistance.
        let startCoordinate = firstTabElement.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let nearbyCoordinate = startCoordinate.withOffset(CGVector(dx: 2, dy: 0))
        startCoordinate.press(forDuration: 0.1, thenDragTo: nearbyCoordinate)

        Thread.sleep(forTimeInterval: 0.5)

        // Assert: the tab should still be at the same index (no reorder occurred)
        let tabAfterDrag = tabBarTabIdentifier(atIndex: 0)
        XCTAssertEqual(
            tabAfterDrag, tabID,
            "Tab should remain at index 0 after a sub-threshold drag"
        )

        // Verify the tab is still tappable by clicking it
        let tabElement = elements(withValue: firstTabValue).firstMatch
        XCTAssertTrue(tabElement.isHittable, "Tab should be hittable after a sub-threshold drag")
        tabElement.click()

        Thread.sleep(forTimeInterval: 0.5)

        // The tab should still exist and be at the same position
        let tabAfterClick = tabBarTabIdentifier(atIndex: 0)
        XCTAssertEqual(
            tabAfterClick, tabID,
            "Tab should remain at index 0 after clicking"
        )
    }
}
