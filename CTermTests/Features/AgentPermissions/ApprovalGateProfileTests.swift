import XCTest
@testable import CTerm

@MainActor
final class ApprovalGateProfileTests: XCTestCase {

    private var savedActiveID: UUID!

    override func setUp() {
        super.setUp()
        AgentGrantStore.shared._resetForTesting()
        savedActiveID = AgentProfileStore.shared.activeProfileID
    }

    override func tearDown() {
        AgentGrantStore.shared.revokeAllSessionGrants()
        AgentGrantStore.shared._resetForTesting()
        AgentProfileStore.shared.activeProfileID = savedActiveID
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeSession(profile: AgentProfile) -> AgentSession {
        let session = AgentSession(
            intent: "test",
            rawPrompt: "test",
            tabID: nil,
            kind: .multiStep,
            backend: .ollama
        )
        session.profileID = profile.id
        return session
    }

    private func evaluate(_ command: String, profile: AgentProfile, gitBranch: String? = "feature/work") -> GateDecision {
        let session = makeSession(profile: profile)
        return ApprovalGate.evaluate(
            action: .shellCommand(command),
            session: session,
            pwd: "/tmp/repo",
            gitBranch: gitBranch
        )
    }

    private func isAutoApprove(_ decision: GateDecision) -> Bool {
        if case .autoApprove = decision { return true }
        return false
    }

    private func isRequireApproval(_ decision: GateDecision) -> Bool {
        if case .requireApproval = decision { return true }
        return false
    }

    private func isHardStop(_ decision: GateDecision) -> Bool {
        if case .hardStop = decision { return true }
        return false
    }

    // MARK: - Read-only profile

    func test_readOnlyProfile_autoApprovesReads() {
        let decision = evaluate("cat README.md", profile: .readOnly)
        XCTAssertTrue(isAutoApprove(decision), "got \(decision)")
    }

    func test_readOnlyProfile_blocksWrites() {
        // sed -i is a write command → blocked by read-only profile
        let decision = evaluate("sed -i '' 's/foo/bar/' file.txt", profile: .readOnly)
        XCTAssertTrue(isRequireApproval(decision), "blocked writes should surface approval sheet; got \(decision)")
    }

    // MARK: - Sandbox-repo profile

    func test_sandboxRepoProfile_autoApprovesReads() {
        let decision = evaluate("ls -la", profile: .sandboxRepo)
        XCTAssertTrue(isAutoApprove(decision), "got \(decision)")
    }

    func test_sandboxRepoProfile_requiresApprovalForWrites() {
        // mv is a write → not auto-approved under sandbox-repo
        let decision = evaluate("mv a.txt b.txt", profile: .sandboxRepo)
        XCTAssertTrue(isRequireApproval(decision), "got \(decision)")
    }

    // MARK: - Full-auto profile

    func test_fullAutoProfile_autoApprovesWrites() {
        let decision = evaluate("mv a.txt b.txt", profile: .fullAuto)
        XCTAssertTrue(isAutoApprove(decision), "got \(decision)")
    }

    func test_fullAutoProfile_stillHonorsHardStops() {
        let decision = evaluate("rm -rf /", profile: .fullAuto)
        XCTAssertTrue(isHardStop(decision), "hard-stops must still fire even in full-auto; got \(decision)")
    }

    // MARK: - No profile (fallback)

    func test_noProfile_readFilesAutoApproves() {
        let session = AgentSession(
            intent: "t", rawPrompt: "t", tabID: nil,
            kind: .multiStep, backend: .ollama
        )
        // profileID is nil by default
        XCTAssertNil(session.profileID)
        let decision = ApprovalGate.evaluate(
            action: .shellCommand("cat README.md"),
            session: session,
            pwd: "/tmp/repo",
            gitBranch: "feature/work"
        )
        // readFiles always auto-approves under the existing trust-mode decide()
        XCTAssertTrue(isAutoApprove(decision), "got \(decision)")
    }
}
