//
//  TerminalBlockStoreTests.swift
//  CTermTests
//
//  Tests for TerminalBlockStore: append + cap, recent(), search(), update(id:).
//

import XCTest
@testable import CTerm

@MainActor
final class TerminalBlockStoreTests: XCTestCase {

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
            exitCode: status == .succeeded ? 0 : 1,
            durationNanoseconds: nil
        )
    }

    func test_append_enforces_cap_at_100() {
        let store = TerminalBlockStore()
        for i in 0..<120 {
            store.append(makeBlock(command: "cmd\(i)"))
        }
        XCTAssertEqual(store.all.count, 100)
        // Newest-first: the most recently appended should be at index 0.
        XCTAssertEqual(store.all.first?.command, "cmd119")
        // Oldest retained: cmd20 (cmd0..cmd19 got evicted).
        XCTAssertEqual(store.all.last?.command, "cmd20")
    }

    func test_recent_returns_newest_first() {
        let store = TerminalBlockStore()
        store.append(makeBlock(command: "first"))
        store.append(makeBlock(command: "second"))
        store.append(makeBlock(command: "third"))

        let recent = store.recent(limit: 2)
        XCTAssertEqual(recent.count, 2)
        XCTAssertEqual(recent[0].command, "third")
        XCTAssertEqual(recent[1].command, "second")
    }

    func test_search_matches_command_text() {
        let store = TerminalBlockStore()
        store.append(makeBlock(command: "git status"))
        store.append(makeBlock(command: "npm install"))
        store.append(makeBlock(command: "git commit"))

        let results = store.search(query: "git")
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.command?.contains("git") == true })
    }

    func test_search_matches_output_snippet_case_insensitive() {
        let store = TerminalBlockStore()
        store.append(makeBlock(command: "ls", output: "Package.swift README.md"))
        store.append(makeBlock(command: "pwd", output: "/Users/test"))

        let results = store.search(query: "package")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.command, "ls")
    }

    func test_search_matches_error_snippet() {
        let store = TerminalBlockStore()
        store.append(makeBlock(command: "swift build", error: "FATAL: missing dep", status: .failed))
        store.append(makeBlock(command: "ls", output: "ok"))

        let results = store.search(query: "FATAL")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.command, "swift build")
    }

    func test_search_empty_query_returns_empty() {
        let store = TerminalBlockStore()
        store.append(makeBlock(command: "ls"))
        XCTAssertTrue(store.search(query: "").isEmpty)
        XCTAssertTrue(store.search(query: "   ").isEmpty)
    }

    func test_update_finds_and_mutates() {
        let store = TerminalBlockStore()
        let block = makeBlock(command: "sleep 5", status: .running)
        store.append(block)

        let didUpdate = store.update(id: block.id) { block in
            block.status = .succeeded
            block.exitCode = 0
            block.outputSnippet = "done"
        }

        XCTAssertTrue(didUpdate)
        let updated = store.find(id: block.id)
        XCTAssertEqual(updated?.status, .succeeded)
        XCTAssertEqual(updated?.exitCode, 0)
        XCTAssertEqual(updated?.outputSnippet, "done")
    }

    func test_update_returns_false_for_missing_id() {
        let store = TerminalBlockStore()
        store.append(makeBlock(command: "ls"))
        let didUpdate = store.update(id: UUID()) { $0.status = .failed }
        XCTAssertFalse(didUpdate)
    }

    func test_evict_keeps_newest_entries() {
        let store = TerminalBlockStore()
        for i in 0..<10 {
            store.append(makeBlock(command: "cmd\(i)"))
        }
        store.evict(keepingLast: 3)
        XCTAssertEqual(store.all.count, 3)
        XCTAssertEqual(store.all.first?.command, "cmd9")
        XCTAssertEqual(store.all.last?.command, "cmd7")
    }
}
