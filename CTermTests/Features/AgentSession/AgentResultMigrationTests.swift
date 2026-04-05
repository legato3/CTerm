import XCTest
@testable import CTerm

/// Verifies the lenient `AgentResult` decoder keeps old snapshots (where
/// `filesChanged` was `[String]`) readable after the move to `[ChangedFile]`.
final class AgentResultMigrationTests: XCTestCase {

    private func jsonDecoder() -> JSONDecoder { JSONDecoder() }
    private func jsonEncoder() -> JSONEncoder { JSONEncoder() }

    func test_legacyStringArray_decodesIntoModifiedChangedFiles() throws {
        let legacy = """
        {
          "summary": "did the thing",
          "filesChanged": ["a.swift", "dir/b.swift", "c.md"],
          "nextActions": [],
          "durationMs": 1234,
          "handoffMemoryKey": null,
          "exitStatus": "succeeded"
        }
        """
        let data = Data(legacy.utf8)
        let decoded = try jsonDecoder().decode(AgentResult.self, from: data)

        XCTAssertEqual(decoded.filesChanged.count, 3)
        XCTAssertEqual(decoded.filesChanged.map(\.path), ["a.swift", "dir/b.swift", "c.md"])
        for file in decoded.filesChanged {
            XCTAssertEqual(file.status, .modified)
            XCTAssertEqual(file.additions, 0)
            XCTAssertEqual(file.deletions, 0)
            XCTAssertNil(file.oldPath)
        }
        XCTAssertEqual(decoded.summary, "did the thing")
        XCTAssertEqual(decoded.durationMs, 1234)
        XCTAssertEqual(decoded.exitStatus, .succeeded)
    }

    func test_emptyLegacyList_decodesToEmpty() throws {
        let legacy = """
        {
          "summary": "noop",
          "filesChanged": [],
          "nextActions": [],
          "durationMs": 0,
          "handoffMemoryKey": null,
          "exitStatus": "succeeded"
        }
        """
        let decoded = try jsonDecoder().decode(AgentResult.self, from: Data(legacy.utf8))
        XCTAssertTrue(decoded.filesChanged.isEmpty)
        XCTAssertTrue(decoded.filesChangedPaths.isEmpty)
    }

    func test_newFormat_roundTripsAllFields() throws {
        let original = AgentResult(
            summary: "refactor",
            filesChanged: [
                ChangedFile(path: "a.swift", status: .added, additions: 12, deletions: 0),
                ChangedFile(path: "b.swift", status: .modified, additions: 4, deletions: 2),
                ChangedFile(path: "c.swift", status: .deleted, additions: 0, deletions: 30),
                ChangedFile(path: "new/d.swift", status: .renamed, additions: 1, deletions: 1, oldPath: "old/d.swift"),
                ChangedFile(path: "untracked.md", status: .untracked, additions: 7, deletions: 0),
            ],
            nextActions: [
                NextAction(label: "Test", prompt: "Run tests", confidence: 0.8),
            ],
            durationMs: 9876,
            handoffMemoryKey: "handoff/key",
            exitStatus: .partial
        )

        let data = try jsonEncoder().encode(original)
        let decoded = try jsonDecoder().decode(AgentResult.self, from: data)

        XCTAssertEqual(decoded.summary, original.summary)
        XCTAssertEqual(decoded.durationMs, original.durationMs)
        XCTAssertEqual(decoded.handoffMemoryKey, original.handoffMemoryKey)
        XCTAssertEqual(decoded.exitStatus, original.exitStatus)
        XCTAssertEqual(decoded.filesChanged.count, 5)
        XCTAssertEqual(decoded.filesChanged, original.filesChanged)
        XCTAssertEqual(decoded.filesChangedPaths, ["a.swift", "b.swift", "c.swift", "new/d.swift", "untracked.md"])

        // Specific status + rename fidelity
        XCTAssertEqual(decoded.filesChanged[0].status, .added)
        XCTAssertEqual(decoded.filesChanged[3].status, .renamed)
        XCTAssertEqual(decoded.filesChanged[3].oldPath, "old/d.swift")
        XCTAssertEqual(decoded.filesChanged[4].status, .untracked)
        XCTAssertEqual(decoded.filesChanged[4].additions, 7)
    }

    func test_changedFile_isIdentifiableByPath() {
        let f = ChangedFile(path: "foo/bar.swift", status: .modified)
        XCTAssertEqual(f.id, "foo/bar.swift")
    }
}
