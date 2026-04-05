import XCTest
@testable import CTerm

@MainActor
final class ModelRouterTests: XCTestCase {

    // MARK: - Default preset

    func test_defaultPresetIsLocalFirst() {
        let router = ModelRouter(presetID: "localFirst")
        router._setOllamaHealthy(true)
        XCTAssertEqual(router.activePresetID, "localFirst")
        XCTAssertEqual(router.activePreset.id, ModelRoutingPreset.localFirst.id)
    }

    // MARK: - localFirst routing

    func test_localFirst_codingUsesClaude() {
        let router = ModelRouter(presetID: "localFirst")
        router._setOllamaHealthy(true)
        XCTAssertEqual(router.pick(role: .coding), .claudeSubscription)
    }

    func test_localFirst_summarizingUsesOllama() {
        let router = ModelRouter(presetID: "localFirst")
        router._setOllamaHealthy(true)
        XCTAssertEqual(router.pick(role: .summarizing), .ollama)
    }

    func test_localFirst_planningUsesOllama() {
        let router = ModelRouter(presetID: "localFirst")
        router._setOllamaHealthy(true)
        XCTAssertEqual(router.pick(role: .planning), .ollama)
    }

    // MARK: - claudeFirst routing

    func test_claudeFirst_planningUsesClaude() {
        let router = ModelRouter(presetID: "claudeFirst")
        router._setOllamaHealthy(true)
        XCTAssertEqual(router.pick(role: .planning), .claudeSubscription)
    }

    func test_claudeFirst_summarizingUsesOllama() {
        let router = ModelRouter(presetID: "claudeFirst")
        router._setOllamaHealthy(true)
        XCTAssertEqual(router.pick(role: .summarizing), .ollama)
    }

    // MARK: - Profile backend override

    func test_profileBackendOverridesPreset() {
        let router = ModelRouter(presetID: "localFirst")
        router._setOllamaHealthy(true)
        // localFirst normally picks claude for coding, but the profile
        // pins ollama — override wins.
        XCTAssertEqual(
            router.pick(role: .coding, profileBackend: .ollama),
            .ollama
        )
    }

    func test_profileBackendOverridesPreset_inverse() {
        let router = ModelRouter(presetID: "allOllama")
        router._setOllamaHealthy(true)
        XCTAssertEqual(
            router.pick(role: .summarizing, profileBackend: .claudeSubscription),
            .claudeSubscription
        )
    }

    // MARK: - Switching preset

    func test_switchingActivePresetUpdatesPick() {
        let router = ModelRouter(presetID: "localFirst")
        router._setOllamaHealthy(true)
        XCTAssertEqual(router.pick(role: .coding), .claudeSubscription)
        router.activePresetID = "allOllama"
        XCTAssertEqual(router.pick(role: .coding), .ollama)
    }

    // MARK: - allOllama / allClaude

    func test_allOllama_returnsOllamaForEveryRole() {
        let router = ModelRouter(presetID: "allOllama")
        router._setOllamaHealthy(true)
        for role in StepRole.allCases {
            XCTAssertEqual(router.pick(role: role), .ollama, "role=\(role)")
        }
    }

    func test_allClaude_returnsClaudeForEveryRole() {
        let router = ModelRouter(presetID: "allClaude")
        router._setOllamaHealthy(true)
        for role in StepRole.allCases {
            XCTAssertEqual(router.pick(role: role), .claudeSubscription, "role=\(role)")
        }
    }

    // MARK: - Invalid persisted ID

    func test_invalidPresetIDFallsBackToLocalFirst() {
        let router = ModelRouter(presetID: "does-not-exist")
        XCTAssertEqual(router.activePresetID, "localFirst")
        XCTAssertEqual(router.activePreset.id, ModelRoutingPreset.localFirst.id)
    }

    // MARK: - Health check fallback

    func test_unhealthyOllamaFallsBackWhenPresetPicksOllama() {
        let router = ModelRouter(presetID: "allOllama")
        router._setOllamaHealthy(false)
        // With ollama unhealthy, planning should fall back to the provided
        // fallback. Pass .claudeSubscription as the fallback to verify the
        // router actually swaps it in.
        XCTAssertEqual(
            router.pick(role: .planning, fallback: .claudeSubscription),
            .claudeSubscription
        )
    }

    func test_unhealthyOllamaDoesNotAffectClaudePick() {
        let router = ModelRouter(presetID: "allClaude")
        router._setOllamaHealthy(false)
        XCTAssertEqual(router.pick(role: .coding), .claudeSubscription)
    }
}
