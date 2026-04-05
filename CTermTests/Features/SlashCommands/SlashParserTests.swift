//
//  SlashParserTests.swift
//  CTermTests
//
//  Tests for SlashParser: prefix detection, command lookup, arg tokenization.
//

import XCTest
@testable import CTerm

@MainActor
final class SlashParserTests: XCTestCase {

    func test_isSlashPrefix_true_when_first_char_is_slash() {
        XCTAssertTrue(SlashParser.isSlashPrefix("/review"))
        XCTAssertTrue(SlashParser.isSlashPrefix("/"))
    }

    func test_isSlashPrefix_false_when_not_at_char_zero() {
        XCTAssertFalse(SlashParser.isSlashPrefix(" /review"))
        XCTAssertFalse(SlashParser.isSlashPrefix("hello"))
        XCTAssertFalse(SlashParser.isSlashPrefix(""))
        XCTAssertFalse(SlashParser.isSlashPrefix("@review"))
    }

    func test_parse_plain_command_returns_empty_args() {
        let inv = SlashParser.parse("/review")
        XCTAssertNotNil(inv)
        XCTAssertEqual(inv?.command.name, "review")
        XCTAssertEqual(inv?.args, [])
    }

    func test_parse_command_with_single_arg() {
        let inv = SlashParser.parse("/explain Tab.swift")
        XCTAssertNotNil(inv)
        XCTAssertEqual(inv?.command.name, "explain")
        XCTAssertEqual(inv?.args, ["Tab.swift"])
    }

    func test_parse_command_with_multiple_whitespace_separated_args() {
        let inv = SlashParser.parse("/plan add dark mode toggle")
        XCTAssertNotNil(inv)
        XCTAssertEqual(inv?.command.name, "plan")
        XCTAssertEqual(inv?.args, ["add", "dark", "mode", "toggle"])
    }

    func test_parse_command_with_quoted_arg() {
        let inv = SlashParser.parse("/explain \"some file.swift\"")
        XCTAssertNotNil(inv)
        XCTAssertEqual(inv?.command.name, "explain")
        XCTAssertEqual(inv?.args, ["some file.swift"])
    }

    func test_parse_command_with_mixed_quoted_and_unquoted_args() {
        let inv = SlashParser.parse("/refactor \"my file.swift\" extra")
        XCTAssertNotNil(inv)
        XCTAssertEqual(inv?.args, ["my file.swift", "extra"])
    }

    func test_parse_unknown_command_returns_nil() {
        XCTAssertNil(SlashParser.parse("/unknownCmd"))
        XCTAssertNil(SlashParser.parse("/unknownCmd arg"))
    }

    func test_parse_empty_string_returns_nil() {
        XCTAssertNil(SlashParser.parse(""))
    }

    func test_parse_bare_slash_returns_nil() {
        XCTAssertNil(SlashParser.parse("/"))
    }

    func test_parse_non_slash_input_returns_nil() {
        XCTAssertNil(SlashParser.parse("review"))
        XCTAssertNil(SlashParser.parse("hello /review"))
    }

    func test_parse_extra_args_kept_as_is() {
        // Commands with no args still accept trailing tokens; parser doesn't enforce.
        let inv = SlashParser.parse("/review extra ignored args")
        XCTAssertNotNil(inv)
        XCTAssertEqual(inv?.command.name, "review")
        XCTAssertEqual(inv?.args, ["extra", "ignored", "args"])
    }

    func test_parse_leading_trailing_whitespace_in_args_trimmed() {
        let inv = SlashParser.parse("/explain    Tab.swift   ")
        XCTAssertEqual(inv?.args, ["Tab.swift"])
    }
}
