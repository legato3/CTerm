//
//  DragDropTests.swift
//  CalyxTests
//
//  Tests for TabBarDragController — pasteboard serialization
//  and drop validation for tab drag-and-drop.
//
//  Coverage:
//  - Custom pasteboard type registration
//  - Write tab UUID to pasteboard
//  - Read tab UUID from pasteboard (valid, invalid, empty)
//  - Validate drop with known vs unknown tab IDs
//

import XCTest
@testable import Calyx

@MainActor
final class DragDropTests: XCTestCase {

    // ==================== Pasteboard Type ====================

    func test_pasteboardType_is_calyx_tabID() {
        XCTAssertEqual(
            TabBarDragController.pasteboardType.rawValue,
            "com.calyx.tabID"
        )
    }

    // ==================== Write to Pasteboard ====================

    func test_writeToPasteboard_writes_tab_uuid_string() {
        let tabID = UUID()
        let pasteboard = NSPasteboard(name: .init("test_\(UUID().uuidString)"))
        pasteboard.clearContents()

        TabBarDragController.writeToPasteboard(pasteboard, tabID: tabID)

        let result = pasteboard.string(forType: TabBarDragController.pasteboardType)
        XCTAssertEqual(result, tabID.uuidString)
    }

    // ==================== Read from Pasteboard ====================

    func test_readFromPasteboard_reads_valid_uuid() {
        let tabID = UUID()
        let pasteboard = NSPasteboard(name: .init("test_\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString(tabID.uuidString, forType: TabBarDragController.pasteboardType)

        let result = TabBarDragController.readFromPasteboard(pasteboard)
        XCTAssertEqual(result, tabID)
    }

    func test_readFromPasteboard_returns_nil_for_invalid_uuid() {
        let pasteboard = NSPasteboard(name: .init("test_\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("not-a-uuid", forType: TabBarDragController.pasteboardType)

        let result = TabBarDragController.readFromPasteboard(pasteboard)
        XCTAssertNil(result)
    }

    func test_readFromPasteboard_returns_nil_for_empty_pasteboard() {
        let pasteboard = NSPasteboard(name: .init("test_\(UUID().uuidString)"))
        pasteboard.clearContents()

        let result = TabBarDragController.readFromPasteboard(pasteboard)
        XCTAssertNil(result)
    }

    // ==================== Validate Drop ====================

    func test_validateDrop_returns_true_for_existing_tab() {
        let group = TabGroup()
        let tab = Tab()
        group.addTab(tab)

        XCTAssertTrue(TabBarDragController.validateDrop(tabID: tab.id, in: group))
    }

    func test_validateDrop_returns_false_for_unknown_tab() {
        let group = TabGroup()

        XCTAssertFalse(TabBarDragController.validateDrop(tabID: UUID(), in: group))
    }
}
