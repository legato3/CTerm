//
//  SlashCommandRegistryTests.swift
//  CTermTests
//
//  Tests for SlashCommandRegistry: built-in presence, lookup, template rendering.
//

import XCTest
@testable import CTerm

@MainActor
final class SlashCommandRegistryTests: XCTestCase {

    private let expectedNames: Set<String> = [
        "review", "explain", "plan", "fix", "test",
        "commit", "simplify", "refactor", "docs"
    ]

    func test_all_nine_builtins_present() {
        let actual = Set(SlashCommandRegistry.builtIn.map(\.name))
        XCTAssertEqual(actual, expectedNames)
        XCTAssertEqual(SlashCommandRegistry.builtIn.count, 9)
    }

    func test_lookup_is_case_sensitive_exact_match() {
        XCTAssertNotNil(SlashCommandRegistry.lookup(name: "review"))
        XCTAssertNil(SlashCommandRegistry.lookup(name: "Review"))
        XCTAssertNil(SlashCommandRegistry.lookup(name: "REVIEW"))
    }

    func test_lookup_unknown_returns_nil() {
        XCTAssertNil(SlashCommandRegistry.lookup(name: "nonexistent"))
        XCTAssertNil(SlashCommandRegistry.lookup(name: ""))
    }

    func test_every_template_renders_non_empty_string() {
        for command in SlashCommandRegistry.builtIn {
            let stubArgs = command.args.map { _ in "placeholder" }
            let invocation = SlashCommandInvocation(command: command, args: stubArgs)
            let rendered = invocation.renderedPrompt
            XCTAssertFalse(
                rendered.isEmpty,
                "template for /\(command.name) returned an empty string"
            )
        }
    }

    func test_explain_template_interpolates_file_arg() {
        guard let cmd = SlashCommandRegistry.lookup(name: "explain") else {
            return XCTFail("explain missing")
        }
        let rendered = SlashCommandInvocation(command: cmd, args: ["Tab.swift"])
            .renderedPrompt
        XCTAssertTrue(rendered.contains("Tab.swift"))
    }

    func test_plan_template_joins_multi_word_goal() {
        guard let cmd = SlashCommandRegistry.lookup(name: "plan") else {
            return XCTFail("plan missing")
        }
        let rendered = SlashCommandInvocation(
            command: cmd,
            args: ["add", "dark", "mode"]
        ).renderedPrompt
        XCTAssertTrue(rendered.contains("add dark mode"))
    }

    func test_matching_empty_query_returns_all() {
        let all = SlashCommandRegistry.matching(query: "")
        XCTAssertEqual(all.count, SlashCommandRegistry.builtIn.count)
    }

    func test_matching_prefix_filters_case_insensitively() {
        let re = SlashCommandRegistry.matching(query: "re")
        let names = Set(re.map(\.name))
        XCTAssertTrue(names.contains("review"))
        XCTAssertTrue(names.contains("refactor"))
        XCTAssertFalse(names.contains("plan"))
    }

    func test_matching_uppercase_prefix_still_matches() {
        let up = SlashCommandRegistry.matching(query: "EX")
        XCTAssertTrue(up.contains { $0.name == "explain" })
    }

    func test_signature_includes_arg_names() {
        guard let cmd = SlashCommandRegistry.lookup(name: "explain") else {
            return XCTFail("explain missing")
        }
        XCTAssertEqual(cmd.signature, "/explain <file>")
    }

    func test_signature_for_no_arg_command() {
        guard let cmd = SlashCommandRegistry.lookup(name: "review") else {
            return XCTFail("review missing")
        }
        XCTAssertEqual(cmd.signature, "/review")
    }

    func test_requiresArg_true_when_required_arg_present() {
        guard let explain = SlashCommandRegistry.lookup(name: "explain") else {
            return XCTFail()
        }
        XCTAssertTrue(explain.requiresArg)
    }

    func test_requiresArg_false_when_no_args() {
        guard let review = SlashCommandRegistry.lookup(name: "review") else {
            return XCTFail()
        }
        XCTAssertFalse(review.requiresArg)
    }
}
