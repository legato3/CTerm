import XCTest
@testable import CTerm

@MainActor
final class AgentPermissionsRegressionTests: XCTestCase {

    override func setUp() {
        super.setUp()
        AgentGrantStore.shared._resetForTesting()
    }

    override func tearDown() {
        AgentGrantStore.shared._resetForTesting()
        super.tearDown()
    }

    func test_hardStopDetectsForcePushToProtectedBranchViaRefspec() {
        let command = "git push --force origin HEAD:main"

        XCTAssertEqual(
            HardStopGuard.isHardStop(command, gitBranch: "feature/work"),
            .forcePushProtected
        )
    }

    func test_browserApprovalRecordsGrantThatGateCanReuse() {
        let presenter = ApprovalPresenter.shared
        let session = AgentSession(
            intent: "Inspect a dashboard",
            rawPrompt: "Inspect a dashboard",
            tabID: nil,
            kind: .multiStep,
            backend: .ollama
        )
        let key = GrantKey.browser(tier: .medium, tool: "browser:click")
        let context = ApprovalContext(
            stepID: nil,
            riskScore: 30,
            riskTier: .medium,
            action: ActionDescriptor(
                what: "Browser: browser:click {\"selector\":\"button.submit\"}",
                why: "Toward goal: Inspect a dashboard",
                impact: "Interactive browser action",
                rollback: nil
            ),
            grantKey: key,
            suggestedScope: .thisTask
        )

        presenter.setRepoPath("/tmp/browser-grant-test")
        presenter.session(session, didRequestApproval: context)
        presenter.resolve(answer: .approved, scope: .thisTask)

        XCTAssertTrue(
            AgentGrantStore.shared.hasGrant(
                key: key,
                in: GrantContext(sessionID: session.id, pwd: "/tmp/browser-grant-test")
            )
        )
    }

    func test_repoGrantLoadsSynchronouslyOnFirstLookupAfterReset() async {
        let repoPath = "/tmp/cterm-repo-grant-sync"
        let repoKey = GrantContext.key(forPwd: repoPath)
        let key = GrantKey(category: .runCommands, riskTier: .medium, commandPrefix: "npm")
        let file = RepoGrantsFile(repoKey: repoKey, repoPath: repoPath, grants: [RepoGrantEntry(key: key)])

        await GrantsPersistence.shared.save(file)
        AgentGrantStore.shared._resetForTesting()
        defer {
            AgentGrantStore.shared._resetForTesting()
            Task { await GrantsPersistence.shared.delete(repoKey: repoKey) }
        }

        XCTAssertTrue(
            AgentGrantStore.shared.hasGrant(
                key: key,
                in: GrantContext(sessionID: UUID(), pwd: repoPath)
            )
        )
    }
}
