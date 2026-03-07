//
//  BrowserIntegrationTests.swift
//  CalyxTests
//
//  Tests for Phase 8 Browser Integration: TabContent.browser case,
//  BrowserSnapshot persistence, BrowserState observable model,
//  and BrowserTabController lifecycle.
//
//  Coverage:
//  - TabContent.browser(url:) variant
//  - BrowserSnapshot JSON encode/decode roundtrip
//  - TabSnapshot with browserURL field
//  - BrowserState initial property values
//  - BrowserTabController create / deactivate lifecycle
//

import XCTest
@testable import Calyx

@MainActor
final class BrowserIntegrationTests: XCTestCase {

    // MARK: - Helpers

    private let exampleURL = URL(string: "https://example.com")!
    private let githubURL = URL(string: "https://github.com/user/repo")!

    // ==================== 1. TabContent.browser Case ====================

    func test_tabContent_browser_stores_url() {
        // Arrange
        let content = TabContent.browser(url: exampleURL)

        // Assert
        if case .browser(let url) = content {
            XCTAssertEqual(url, exampleURL, "browser case should store the URL")
        } else {
            XCTFail("Expected .browser case")
        }
    }

    func test_tab_with_browser_content_exposes_url() {
        // Arrange
        let tab = Tab(title: "Browser", content: .browser(url: githubURL))

        // Assert
        if case .browser(let url) = tab.content {
            XCTAssertEqual(url, githubURL)
        } else {
            XCTFail("Tab content should be .browser")
        }
    }

    func test_tab_with_terminal_content_still_works() {
        // Arrange
        let tab = Tab(title: "Terminal", content: .terminal)

        // Assert
        if case .terminal = tab.content {
            // Pass — terminal case unchanged
        } else {
            XCTFail("Tab content should be .terminal")
        }
    }

    // ==================== 2. BrowserSnapshot Encode/Decode ====================

    func test_browserSnapshot_roundtrip() throws {
        // Arrange
        let original = BrowserSnapshot(url: exampleURL)

        // Act
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BrowserSnapshot.self, from: data)

        // Assert
        XCTAssertEqual(decoded.url, exampleURL, "URL should survive JSON roundtrip")
    }

    func test_browserSnapshot_preserves_complex_url() throws {
        // Arrange
        let complexURL = URL(string: "https://example.com/path?q=hello&lang=en#section")!
        let original = BrowserSnapshot(url: complexURL)

        // Act
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BrowserSnapshot.self, from: data)

        // Assert
        XCTAssertEqual(decoded.url, complexURL, "Complex URL with query and fragment should be preserved")
    }

    // ==================== 3. TabSnapshot with browserURL ====================

    func test_tabSnapshot_with_browserURL_roundtrip() throws {
        // Arrange
        let original = TabSnapshot(
            id: UUID(),
            title: "Docs",
            pwd: nil,
            splitTree: SplitTree(),
            browserURL: exampleURL
        )

        // Act
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TabSnapshot.self, from: data)

        // Assert
        XCTAssertEqual(decoded.browserURL, exampleURL, "browserURL should survive roundtrip")
        XCTAssertEqual(decoded.title, "Docs")
    }

    func test_tabSnapshot_browserURL_nil_for_terminal_tabs() throws {
        // Arrange
        let original = TabSnapshot(
            id: UUID(),
            title: "Terminal",
            pwd: "/home",
            splitTree: SplitTree()
        )

        // Act
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TabSnapshot.self, from: data)

        // Assert
        XCTAssertNil(decoded.browserURL, "browserURL should be nil for terminal tabs")
    }

    func test_sessionSnapshot_roundtrip_with_browser_tab() throws {
        // Arrange
        let browserTab = TabSnapshot(
            id: UUID(), title: "Browser", pwd: nil,
            splitTree: SplitTree(), browserURL: githubURL
        )
        let terminalTab = TabSnapshot(
            id: UUID(), title: "Terminal", pwd: "/home",
            splitTree: SplitTree()
        )
        let group = TabGroupSnapshot(
            id: UUID(), name: "Default",
            tabs: [browserTab, terminalTab],
            activeTabID: browserTab.id
        )
        let window = WindowSnapshot(
            id: UUID(),
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            groups: [group],
            activeGroupID: group.id
        )
        let snapshot = SessionSnapshot(windows: [window])

        // Act
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(SessionSnapshot.self, from: data)

        // Assert
        let tabs = decoded.windows[0].groups[0].tabs
        XCTAssertEqual(tabs[0].browserURL, githubURL, "Browser tab URL should be preserved")
        XCTAssertNil(tabs[1].browserURL, "Terminal tab browserURL should remain nil")
    }

    // ==================== 4. BrowserState Initial Values ====================

    func test_browserState_initial_url() {
        // Arrange & Act
        let state = BrowserState(url: exampleURL)

        // Assert
        XCTAssertEqual(state.url, exampleURL, "Initial URL should match")
    }

    func test_browserState_initial_loading_false() {
        // Arrange & Act
        let state = BrowserState(url: exampleURL)

        // Assert
        XCTAssertFalse(state.isLoading, "isLoading should default to false")
    }

    func test_browserState_initial_navigation_flags() {
        // Arrange & Act
        let state = BrowserState(url: exampleURL)

        // Assert
        XCTAssertFalse(state.canGoBack, "canGoBack should default to false")
        XCTAssertFalse(state.canGoForward, "canGoForward should default to false")
    }

    func test_browserState_title_defaults_to_host() {
        // Arrange & Act
        let state = BrowserState(url: githubURL)

        // Assert
        XCTAssertEqual(state.title, "github.com",
                       "Title should default to URL host")
    }

    // ==================== 5. BrowserTabController Lifecycle ====================

    func test_controller_creates_browserState_with_url() {
        // Arrange & Act
        let controller = BrowserTabController(url: exampleURL)

        // Assert
        XCTAssertNotNil(controller.browserState, "browserState should be created on init")
        XCTAssertEqual(controller.browserState?.url, exampleURL)
    }

    func test_controller_deactivate_clears_state() {
        // Arrange
        let controller = BrowserTabController(url: exampleURL)
        XCTAssertNotNil(controller.browserState, "Precondition: browserState exists")

        // Act
        controller.deactivate()

        // Assert
        XCTAssertNil(controller.browserState,
                     "browserState should be nil after deactivate()")
    }
}
