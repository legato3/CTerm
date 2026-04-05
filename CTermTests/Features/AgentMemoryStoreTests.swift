import XCTest
@testable import CTerm

final class AgentMemoryStoreTests: XCTestCase {

    func test_projectKeyUsesNearestGitRootDirectory() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repoRoot = base.appendingPathComponent("repos/My Repo", isDirectory: true)
        let nested = repoRoot.appendingPathComponent("Sources/App", isDirectory: true)

        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: repoRoot.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )

        XCTAssertEqual(
            AgentMemoryStore.key(for: nested.path),
            "tmp_repos_My-Repo"
        )
    }

    func test_projectKeyTreatsGitWorktreeMarkerFileAsRepoRoot() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repoRoot = base.appendingPathComponent("workspace/project", isDirectory: true)
        let nested = repoRoot.appendingPathComponent("pkg/module", isDirectory: true)

        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try "gitdir: /tmp/worktrees/project".write(
            to: repoRoot.appendingPathComponent(".git"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertEqual(
            AgentMemoryStore.key(for: nested.path),
            "tmp_workspace_project"
        )
    }

    func test_projectKeyFallsBackToWorkingDirectoryWhenNotInGitRepo() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let nested = base.appendingPathComponent("one/two/three", isDirectory: true)

        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        XCTAssertEqual(
            AgentMemoryStore.key(for: nested.path),
            "one_two_three"
        )
    }
}
