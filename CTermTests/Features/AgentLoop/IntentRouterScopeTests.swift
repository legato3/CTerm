import Testing
@testable import CTerm

@Suite("Intent Router Scope")
struct IntentRouterScopeTests {

    @Test("System goals are scoped to the machine, not the repo")
    func inferSystemScope() {
        #expect(IntentRouter.inferScope("check for issues on my mac") == .system)
    }

    @Test("Repo goals stay project-scoped")
    func inferProjectScope() {
        #expect(IntentRouter.inferScope("check git status in this repo") == .project)
    }

    @Test("Low-confidence system goals avoid repo-inspection fallback")
    func lowConfidenceSystemFallbackIsNotInspectRepo() {
        let result = IntentRouter.classify("check for issues on my mac", scope: .system)
        #expect(result.category == .runWorkflow)
    }

    @Test("Low-confidence general goals prefer explanation over blind execution")
    func lowConfidenceGeneralFallbackExplains() {
        let result = IntentRouter.classify("tell me something useful", scope: .general)
        #expect(result.category == .explain)
    }
}
