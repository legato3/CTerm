//
//  BlockNavigatorFilterTests.swift
//  CTermTests
//
//  Tests for BlockNavigatorFilter — the pure filter helper behind the block
//  navigator sidebar. Covers search, status, scope, and combined (AND)
//  filtering across multiple fabricated tabs.
//

import XCTest
@testable import CTerm

@MainActor
final class BlockNavigatorFilterTests: XCTestCase {

    private let tabAID = UUID()
    private let tabBID = UUID()

    private func makeBlock(
        command: String,
        output: String? = nil,
        error: String? = nil,
        status: TerminalCommandStatus = .succeeded
    ) -> TerminalCommandBlock {
        TerminalCommandBlock(
            id: UUID(),
            source: .shell,
            surfaceID: nil,
            command: command,
            startedAt: Date(),
            finishedAt: Date(),
            status: status,
            outputSnippet: output,
            errorSnippet: error,
            exitCode: status == .succeeded ? 0 : (status == .failed ? 1 : nil),
            durationNanoseconds: nil
        )
    }

    private func makeCorpus() -> [BlockWithTab] {
        // Tab A — 5 blocks mixed statuses
        let a1 = BlockWithTab(block: makeBlock(command: "git status", output: "clean"), tabID: tabAID, tabTitle: "A")
        let a2 = BlockWithTab(block: makeBlock(command: "npm test", error: "FAIL", status: .failed), tabID: tabAID, tabTitle: "A")
        let a3 = BlockWithTab(block: makeBlock(command: "ls -la", output: "drwx"), tabID: tabAID, tabTitle: "A")
        let a4 = BlockWithTab(block: makeBlock(command: "cargo build", status: .running), tabID: tabAID, tabTitle: "A")
        let a5 = BlockWithTab(block: makeBlock(command: "echo HELLO", output: "HELLO"), tabID: tabAID, tabTitle: "A")

        // Tab B — 4 blocks
        let b1 = BlockWithTab(block: makeBlock(command: "git log", output: "commit abc"), tabID: tabBID, tabTitle: "B")
        let b2 = BlockWithTab(block: makeBlock(command: "pytest", error: "boom", status: .failed), tabID: tabBID, tabTitle: "B")
        let b3 = BlockWithTab(block: makeBlock(command: "python run.py", status: .running), tabID: tabBID, tabTitle: "B")
        let b4 = BlockWithTab(block: makeBlock(command: "cat file.txt", output: "hello world"), tabID: tabBID, tabTitle: "B")

        return [a1, a2, a3, a4, a5, b1, b2, b3, b4]
    }

    // MARK: - Search

    func test_search_matches_command_text_case_insensitive() {
        let corpus = makeCorpus()
        let result = BlockNavigatorFilter.apply(
            blocks: corpus,
            scope: .allTabs,
            currentTabID: nil,
            status: .all,
            searchQuery: "GIT"
        )
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.allSatisfy { ($0.block.command ?? "").lowercased().contains("git") })
    }

    func test_search_matches_output_snippet() {
        let corpus = makeCorpus()
        let result = BlockNavigatorFilter.apply(
            blocks: corpus,
            scope: .allTabs,
            currentTabID: nil,
            status: .all,
            searchQuery: "hello world"
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.block.command, "cat file.txt")
    }

    func test_search_matches_error_snippet() {
        let corpus = makeCorpus()
        let result = BlockNavigatorFilter.apply(
            blocks: corpus,
            scope: .allTabs,
            currentTabID: nil,
            status: .all,
            searchQuery: "boom"
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.block.command, "pytest")
    }

    func test_empty_search_returns_all() {
        let corpus = makeCorpus()
        let result = BlockNavigatorFilter.apply(
            blocks: corpus,
            scope: .allTabs,
            currentTabID: nil,
            status: .all,
            searchQuery: "   "
        )
        XCTAssertEqual(result.count, corpus.count)
    }

    // MARK: - Status filter

    func test_status_succeeded_only() {
        let corpus = makeCorpus()
        let result = BlockNavigatorFilter.apply(
            blocks: corpus,
            scope: .allTabs,
            currentTabID: nil,
            status: .succeeded,
            searchQuery: ""
        )
        XCTAssertTrue(result.allSatisfy { $0.block.status == .succeeded })
        XCTAssertEqual(result.count, 5)
    }

    func test_status_failed_only() {
        let corpus = makeCorpus()
        let result = BlockNavigatorFilter.apply(
            blocks: corpus,
            scope: .allTabs,
            currentTabID: nil,
            status: .failed,
            searchQuery: ""
        )
        XCTAssertTrue(result.allSatisfy { $0.block.status == .failed })
        XCTAssertEqual(result.count, 2)
    }

    func test_status_running_only() {
        let corpus = makeCorpus()
        let result = BlockNavigatorFilter.apply(
            blocks: corpus,
            scope: .allTabs,
            currentTabID: nil,
            status: .running,
            searchQuery: ""
        )
        XCTAssertTrue(result.allSatisfy { $0.block.status == .running })
        XCTAssertEqual(result.count, 2)
    }

    // MARK: - Scope filter

    func test_scope_current_tab_only() {
        let corpus = makeCorpus()
        let result = BlockNavigatorFilter.apply(
            blocks: corpus,
            scope: .currentTab,
            currentTabID: tabAID,
            status: .all,
            searchQuery: ""
        )
        XCTAssertTrue(result.allSatisfy { $0.tabID == tabAID })
        XCTAssertEqual(result.count, 5)
    }

    func test_scope_all_tabs_returns_everything() {
        let corpus = makeCorpus()
        let result = BlockNavigatorFilter.apply(
            blocks: corpus,
            scope: .allTabs,
            currentTabID: tabAID,
            status: .all,
            searchQuery: ""
        )
        XCTAssertEqual(result.count, corpus.count)
    }

    func test_scope_current_tab_with_nil_id_returns_empty() {
        let corpus = makeCorpus()
        let result = BlockNavigatorFilter.apply(
            blocks: corpus,
            scope: .currentTab,
            currentTabID: nil,
            status: .all,
            searchQuery: ""
        )
        XCTAssertEqual(result.count, 0)
    }

    // MARK: - AND semantics

    func test_combined_search_status_scope_and_semantics() {
        let corpus = makeCorpus()
        // current tab only = A, status = failed, search = "npm"
        // -> only a2 (npm test / FAIL)
        let result = BlockNavigatorFilter.apply(
            blocks: corpus,
            scope: .currentTab,
            currentTabID: tabAID,
            status: .failed,
            searchQuery: "npm"
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.block.command, "npm test")
        XCTAssertEqual(result.first?.block.status, .failed)
        XCTAssertEqual(result.first?.tabID, tabAID)
    }

    func test_combined_filters_can_produce_empty() {
        let corpus = makeCorpus()
        // Search "nonexistent" → empty even with all-scope
        let result = BlockNavigatorFilter.apply(
            blocks: corpus,
            scope: .allTabs,
            currentTabID: nil,
            status: .all,
            searchQuery: "nonexistent"
        )
        XCTAssertEqual(result.count, 0)
    }

    func test_status_failed_with_scope_tab_b() {
        let corpus = makeCorpus()
        let result = BlockNavigatorFilter.apply(
            blocks: corpus,
            scope: .currentTab,
            currentTabID: tabBID,
            status: .failed,
            searchQuery: ""
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.block.command, "pytest")
    }
}
