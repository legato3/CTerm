//
//  BlockMentionTests.swift
//  CTermTests
//
//  Tests for @block:<shortID> token resolution in AgentPromptContextBuilder
//  and the BlockMentionToken helper.
//

import XCTest
@testable import CTerm

@MainActor
final class BlockMentionTokenTests: XCTestCase {

    func test_shortID_returns_first_8_hex_chars() {
        let uuid = UUID()
        let short = BlockMentionToken.shortID(for: uuid)
        XCTAssertEqual(short.count, 8)
        XCTAssertEqual(short, uuid.uuidString.lowercased().prefix(8).description)
    }

    func test_token_format() {
        let uuid = UUID()
        let token = BlockMentionToken.token(for: uuid)
        XCTAssertTrue(token.hasPrefix("@block:"))
        XCTAssertEqual(token.count, "@block:".count + 8)
    }

    func test_extractShortIDs_finds_all_tokens() {
        let text = "fix @block:abc12345 and also @block:def00099 please"
        let ids = BlockMentionToken.extractShortIDs(from: text)
        XCTAssertEqual(ids, ["abc12345", "def00099"])
    }

    func test_extractShortIDs_returns_empty_when_absent() {
        XCTAssertTrue(BlockMentionToken.extractShortIDs(from: "nothing here").isEmpty)
    }

    func test_stripTokens_removes_tokens_and_normalizes_spaces() {
        let text = "fix @block:abc12345 and @block:def00099 please"
        let stripped = BlockMentionToken.stripTokens(from: text)
        XCTAssertEqual(stripped, "fix and please")
    }
}

@MainActor
final class BlockMentionResolutionTests: XCTestCase {

    private func makeBlock(id: UUID, command: String) -> TerminalCommandBlock {
        TerminalCommandBlock(
            id: id,
            source: .shell,
            surfaceID: nil,
            command: command,
            startedAt: Date(),
            finishedAt: Date(),
            status: .failed,
            outputSnippet: "build output here",
            errorSnippet: "ERROR: failed to compile",
            exitCode: 1,
            durationNanoseconds: nil
        )
    }

    func test_buildPrompt_resolves_token_to_block_content() {
        let id = UUID()
        let tab = Tab(title: "Term", pwd: nil)
        tab.blockStore.append(makeBlock(id: id, command: "swift build"))

        let short = BlockMentionToken.shortID(for: id)
        let goal = "explain @block:\(short) for me"
        let prompt = AgentPromptContextBuilder.buildPrompt(goal: goal, activeTab: tab)

        // Token stripped from visible goal.
        XCTAssertFalse(prompt.contains("@block:\(short)"),
                       "the raw token should be stripped from the visible prompt")
        XCTAssertTrue(prompt.contains("explain"))
        XCTAssertTrue(prompt.contains("for me"))
        // Resolved block content appears in the attached-blocks section.
        XCTAssertTrue(prompt.contains("<attached_terminal_blocks>"),
                      "resolved tokens should append an attached_terminal_blocks section")
        XCTAssertTrue(prompt.contains("Command: swift build"))
    }

    func test_buildPrompt_unresolvable_token_is_stripped_without_error() {
        let tab = Tab(title: "Term", pwd: nil)
        // No blocks added — token can't resolve.
        let goal = "look at @block:deadbeef please"
        let prompt = AgentPromptContextBuilder.buildPrompt(goal: goal, activeTab: tab)

        XCTAssertFalse(prompt.contains("@block:deadbeef"))
        XCTAssertTrue(prompt.contains("look at"))
        XCTAssertTrue(prompt.contains("please"))
        // No attached_terminal_blocks section because no resolved block.
        XCTAssertFalse(prompt.contains("<attached_terminal_blocks>"))
    }

    func test_buildPrompt_unions_token_ids_with_attachedBlockIDs() {
        let id1 = UUID()
        let id2 = UUID()
        let tab = Tab(title: "Term", pwd: nil)
        tab.blockStore.append(makeBlock(id: id1, command: "explicit attached"))
        tab.blockStore.append(makeBlock(id: id2, command: "token referenced"))
        tab.attachBlock(id1)

        let short2 = BlockMentionToken.shortID(for: id2)
        let goal = "compare these @block:\(short2)"
        let prompt = AgentPromptContextBuilder.buildPrompt(goal: goal, activeTab: tab)

        XCTAssertTrue(prompt.contains("Command: explicit attached"))
        XCTAssertTrue(prompt.contains("Command: token referenced"))
    }
}
