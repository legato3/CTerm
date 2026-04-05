//
//  BlockMentionPopoverCoordinatorTests.swift
//  CTermTests
//
//  Tests for BlockMentionPopoverCoordinator selection clamping logic.
//

import XCTest
@testable import CTerm

@MainActor
final class BlockMentionPopoverCoordinatorTests: XCTestCase {

    func test_moveDown_clamps_to_last_item() {
        let coord = BlockMentionPopoverCoordinator()
        coord.itemCount = 3
        coord.selectedIndex = 0
        coord.moveDown()
        XCTAssertEqual(coord.selectedIndex, 1)
        coord.moveDown()
        XCTAssertEqual(coord.selectedIndex, 2)
        coord.moveDown()
        XCTAssertEqual(coord.selectedIndex, 2, "should not exceed itemCount - 1")
    }

    func test_moveUp_clamps_to_zero() {
        let coord = BlockMentionPopoverCoordinator()
        coord.itemCount = 3
        coord.selectedIndex = 2
        coord.moveUp()
        XCTAssertEqual(coord.selectedIndex, 1)
        coord.moveUp()
        XCTAssertEqual(coord.selectedIndex, 0)
        coord.moveUp()
        XCTAssertEqual(coord.selectedIndex, 0, "should not go below 0")
    }

    func test_moveDown_with_empty_list_is_noop() {
        let coord = BlockMentionPopoverCoordinator()
        coord.itemCount = 0
        coord.selectedIndex = 0
        coord.moveDown()
        XCTAssertEqual(coord.selectedIndex, 0)
    }

    func test_moveUp_with_empty_list_is_noop() {
        let coord = BlockMentionPopoverCoordinator()
        coord.itemCount = 0
        coord.selectedIndex = 0
        coord.moveUp()
        XCTAssertEqual(coord.selectedIndex, 0)
    }

    func test_resetSelection_sets_itemCount_and_zeroes_index() {
        let coord = BlockMentionPopoverCoordinator()
        coord.itemCount = 10
        coord.selectedIndex = 7
        coord.resetSelection(itemCount: 4)
        XCTAssertEqual(coord.itemCount, 4)
        XCTAssertEqual(coord.selectedIndex, 0)
    }

    func test_clampSelection_within_bounds_is_noop() {
        let coord = BlockMentionPopoverCoordinator()
        coord.itemCount = 5
        coord.selectedIndex = 2
        coord.clampSelection()
        XCTAssertEqual(coord.selectedIndex, 2)
    }

    func test_clampSelection_over_upper_bound_clamps() {
        let coord = BlockMentionPopoverCoordinator()
        coord.itemCount = 5
        coord.selectedIndex = 99
        coord.clampSelection()
        XCTAssertEqual(coord.selectedIndex, 4)
    }

    func test_clampSelection_below_zero_clamps() {
        let coord = BlockMentionPopoverCoordinator()
        coord.itemCount = 5
        coord.selectedIndex = -3
        coord.clampSelection()
        XCTAssertEqual(coord.selectedIndex, 0)
    }

    func test_clampSelection_with_empty_resets_to_zero() {
        let coord = BlockMentionPopoverCoordinator()
        coord.itemCount = 0
        coord.selectedIndex = 5
        coord.clampSelection()
        XCTAssertEqual(coord.selectedIndex, 0)
    }
}
