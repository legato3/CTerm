// GitServiceHunkRevertTests.swift
// CTermTests
//
// Unit tests for GitService.buildHunkPatch — the pure patch-reconstruction
// helper used by per-hunk revert. Integration tests against a real git repo
// are intentionally omitted: the test suite has no existing helpers for
// constructing temp repos, and adding that infrastructure is out of scope
// for this change. The pure tests cover the bytes we actually ship to
// `git apply -R`; a failing apply surfaces as a GitError to the caller.

import XCTest
@testable import CTerm

@MainActor
final class GitServiceHunkRevertTests: XCTestCase {

    // MARK: - Modified-file hunk

    func test_buildHunkPatch_modifiedFile() {
        let hunk = DiffHunk(
            header: "@@ -1,3 +1,4 @@",
            oldStart: 1, oldCount: 3,
            newStart: 1, newCount: 4,
            bodyLines: [
                " context line",
                "-deleted line",
                "+added one",
                "+added two",
                " trailing"
            ]
        )
        let patch = GitService.buildHunkPatch(filePath: "src/foo.swift", hunk: hunk)
        let expected = """
        diff --git a/src/foo.swift b/src/foo.swift
        --- a/src/foo.swift
        +++ b/src/foo.swift
        @@ -1,3 +1,4 @@
         context line
        -deleted line
        +added one
        +added two
         trailing

        """
        XCTAssertEqual(patch, expected)
        XCTAssertTrue(patch.hasSuffix("\n"))
        XCTAssertFalse(patch.hasSuffix("\n\n"))
    }

    // MARK: - Addition-only hunk

    func test_buildHunkPatch_additionOnly() {
        let hunk = DiffHunk(
            header: "@@ -5,0 +6,2 @@",
            oldStart: 5, oldCount: 0,
            newStart: 6, newCount: 2,
            bodyLines: [
                "+new line 1",
                "+new line 2"
            ]
        )
        let patch = GitService.buildHunkPatch(filePath: "newfile.txt", hunk: hunk)
        XCTAssertTrue(patch.contains("@@ -5,0 +6,2 @@"))
        XCTAssertTrue(patch.contains("diff --git a/newfile.txt b/newfile.txt"))
        XCTAssertTrue(patch.contains("--- a/newfile.txt"))
        XCTAssertTrue(patch.contains("+++ b/newfile.txt"))
        XCTAssertTrue(patch.contains("+new line 1"))
        XCTAssertTrue(patch.contains("+new line 2"))
        XCTAssertTrue(patch.hasSuffix("\n"))
        XCTAssertFalse(patch.hasSuffix("\n\n"))
    }

    // MARK: - Deletion-only hunk

    func test_buildHunkPatch_deletionOnly() {
        let hunk = DiffHunk(
            header: "@@ -10,2 +9,0 @@",
            oldStart: 10, oldCount: 2,
            newStart: 9, newCount: 0,
            bodyLines: [
                "-gone line 1",
                "-gone line 2"
            ]
        )
        let patch = GitService.buildHunkPatch(filePath: "old/path.swift", hunk: hunk)
        XCTAssertTrue(patch.contains("@@ -10,2 +9,0 @@"))
        XCTAssertTrue(patch.contains("-gone line 1"))
        XCTAssertTrue(patch.contains("-gone line 2"))
        XCTAssertTrue(patch.hasSuffix("\n"))
        XCTAssertFalse(patch.hasSuffix("\n\n"))
    }

    // MARK: - Function-context tail on header

    func test_buildHunkPatch_preservesHeaderTail() {
        let hunk = DiffHunk(
            header: "@@ -1,3 +1,3 @@ func example() {",
            oldStart: 1, oldCount: 3,
            newStart: 1, newCount: 3,
            bodyLines: [
                " a",
                "-b",
                "+c",
                " d"
            ]
        )
        let patch = GitService.buildHunkPatch(filePath: "f.swift", hunk: hunk)
        // The function-context suffix after the closing `@@` must be preserved.
        XCTAssertTrue(patch.contains("@@ -1,3 +1,3 @@ func example() {"))
    }

    // MARK: - No trailing blank line even if body already ends with newline-y content

    func test_buildHunkPatch_alwaysSingleTrailingNewline() {
        let hunk = DiffHunk(
            header: "@@ -1,1 +1,1 @@",
            oldStart: 1, oldCount: 1,
            newStart: 1, newCount: 1,
            bodyLines: ["-x", "+y"]
        )
        let patch = GitService.buildHunkPatch(filePath: "t.txt", hunk: hunk)
        XCTAssertTrue(patch.hasSuffix("+y\n"))
        XCTAssertFalse(patch.hasSuffix("\n\n"))
    }
}
