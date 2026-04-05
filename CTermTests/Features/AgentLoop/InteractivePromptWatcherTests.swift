import XCTest
@testable import CTerm

@MainActor
final class InteractivePromptWatcherTests: XCTestCase {

    // MARK: - Pattern matching

    func test_yesNoPrompts_match() {
        let cases: [(String, String)] = [
            ("Continue? [y/N]", "continue_confirm"),
            ("Overwrite? [y/N]", "overwrite"),
            ("Overwrite? (y/n)", "overwrite"),
            ("Are you sure? [y/N]", "are_you_sure"),
            ("Are you sure? (yes/no)", "are_you_sure"),
            ("Delete this file? [Y/n]", "yes_no"),
            ("Proceed (y/n)?", "yes_no"),
        ]

        for (line, expected) in cases {
            let result = InteractivePromptWatcher.match(lines: [line])
            XCTAssertNotNil(result, "Expected match for: \(line)")
            XCTAssertEqual(result?.0.id, expected, "Wrong pattern for: \(line)")
        }
    }

    func test_pressReturn_matches() {
        let cases = [
            "Press RETURN to continue",
            "Press ENTER to continue",
            "Press any key to continue",
            "Press <RETURN> to continue",
        ]
        for line in cases {
            let result = InteractivePromptWatcher.match(lines: [line])
            XCTAssertNotNil(result, "Expected match for: \(line)")
            XCTAssertEqual(result?.0.id, "press_return", "Wrong pattern for: \(line)")
            XCTAssertEqual(result?.0.defaultResponse, "\n")
        }
    }

    func test_passwordPrompts_match_andAreSensitive() {
        let cases = [
            "Password:",
            "Password for chris:",
            "password:",
            "Passphrase:",
            "Passphrase for key /tmp/id_rsa:",
        ]
        for line in cases {
            let result = InteractivePromptWatcher.match(lines: [line])
            XCTAssertNotNil(result, "Expected match for: \(line)")
            XCTAssertEqual(result?.0.id, "password")
            XCTAssertTrue(result?.0.isSensitive ?? false, "Password should be sensitive")
            XCTAssertNil(result?.0.defaultResponse, "Password has no default response")
        }
    }

    func test_nonPromptText_doesNotMatch() {
        let cases = [
            "Regular command output",
            "File created successfully",
            "error: command not found",
            "123 files changed",
            "",
        ]
        for line in cases {
            let result = InteractivePromptWatcher.match(lines: [line])
            XCTAssertNil(result, "Should not match: '\(line)'")
        }
    }

    func test_promptTextMidOutput_doesNotFire_whenNotLastLine() {
        // Prompt text appears earlier but a subsequent line pushes past it:
        // the program has moved on, no prompt is active.
        let lines = [
            "Running task",
            "Overwrite? [y/N]",
            "Done",
        ]
        let result = InteractivePromptWatcher.match(lines: lines)
        XCTAssertNil(result, "Should not match when prompt is not the last line")
    }

    func test_promptAtLastLine_fires() {
        let lines = [
            "Processing files",
            "12 files changed",
            "Continue? [y/N]",
        ]
        let result = InteractivePromptWatcher.match(lines: lines)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.0.id, "continue_confirm")
    }

    func test_trailingWhitespaceOrCursor_stillMatches() {
        // Viewport text may have trailing whitespace or a trailing `$` cursor marker
        let cases = [
            "Continue? [y/N] ",
            "Continue? [y/N]",
        ]
        for line in cases {
            // trailing whitespace is trimmed by trailingNonEmptyLines; simulate that
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let result = InteractivePromptWatcher.match(lines: [trimmed])
            XCTAssertNotNil(result, "Expected match for: '\(line)'")
        }
    }

    // MARK: - trailingNonEmptyLines

    func test_trailingNonEmptyLines_skipsBlankLines() {
        let text = """
        first line

        second line


        third line

        """
        let lines = InteractivePromptWatcher.trailingNonEmptyLines(text, count: 4)
        XCTAssertEqual(lines, ["first line", "second line", "third line"])
    }

    func test_trailingNonEmptyLines_returnsLastN() {
        let text = (1...10).map { "line \($0)" }.joined(separator: "\n")
        let lines = InteractivePromptWatcher.trailingNonEmptyLines(text, count: 4)
        XCTAssertEqual(lines, ["line 7", "line 8", "line 9", "line 10"])
    }

    // MARK: - Debounce hashing

    func test_debounceHash_sameLineSamePatternIsEqual() {
        let a = InteractivePromptWatcher.hashFor(patternID: "yes_no", line: "Continue? [y/N]")
        let b = InteractivePromptWatcher.hashFor(patternID: "yes_no", line: "Continue? [y/N]")
        XCTAssertEqual(a, b)
    }

    func test_debounceHash_differentLineGivesDifferentHash() {
        let a = InteractivePromptWatcher.hashFor(patternID: "yes_no", line: "Continue? [y/N]")
        let b = InteractivePromptWatcher.hashFor(patternID: "yes_no", line: "Proceed? [y/N]")
        XCTAssertNotEqual(a, b)
    }

    func test_debounceHash_differentPatternGivesDifferentHash() {
        let a = InteractivePromptWatcher.hashFor(patternID: "yes_no", line: "Continue? [y/N]")
        let b = InteractivePromptWatcher.hashFor(patternID: "continue_confirm", line: "Continue? [y/N]")
        XCTAssertNotEqual(a, b)
    }
}
