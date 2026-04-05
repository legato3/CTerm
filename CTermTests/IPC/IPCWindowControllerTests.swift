import XCTest
@testable import CTerm

@MainActor
final class IPCWindowControllerTests: XCTestCase {
    func test_handleLaunchWorkflow_autoStartDeliversRolePromptsWithoutPeerRegistration() {
        let session = WindowSession(initialTab: Tab(title: "Terminal", pwd: "/tmp"))
        let server = CTermMCPServer(testToken: "test-token")
        let controller = IPCWindowController(mcpServer: server, windowSession: session)

        controller.onCreateNewTab = { pwd in
            let tab = Tab(title: "Terminal", pwd: pwd)
            session.activeGroup?.addTab(tab)
            session.activeGroup?.activeTabID = tab.id
        }

        var launchedCommands: [(String, String)] = []
        controller.launchRuntimeCommandOverride = { tab, command in
            launchedCommands.append((tab.title, command))
            return true
        }

        let promptsDelivered = expectation(description: "role prompts delivered")
        promptsDelivered.expectedFulfillmentCount = 2

        var deliveredPrompts: [(String, String, AgentInputStyle)] = []
        controller.deliverRolePromptOverride = { tab, prompt, inputStyle in
            deliveredPrompts.append((tab.title, prompt, inputStyle))
            promptsDelivered.fulfill()
            return true
        }

        controller.handleLaunchWorkflow(
            event: CTermIPCLaunchWorkflowEvent(
                roleNames: ["orchestrator", "implementer"],
                autoStart: true,
                sessionName: "Auth Pair",
                initialTask: "Fix auth flow",
                workingDirectory: "/tmp",
                skipDirectoryPrompt: true,
                runtime: AgentRuntimeConfiguration(preset: .claudeCode)
            )
        )

        waitForExpectations(timeout: 5.0)

        XCTAssertEqual(session.activeGroup?.name, "Auth Pair")
        XCTAssertEqual(launchedCommands.map(\.1), ["claude", "claude"])
        XCTAssertEqual(deliveredPrompts.map(\.0), ["orchestrator", "implementer"])
        XCTAssertTrue(deliveredPrompts.allSatisfy { $0.1.contains("Fix auth flow") })
        XCTAssertTrue(deliveredPrompts.allSatisfy { $0.2 == .confirmPasteThenSubmit })
        XCTAssertTrue(
            deliveredPrompts.contains { roleName, prompt, _ in
                roleName == "orchestrator" && prompt.contains("register_peer with name \"orchestrator\"")
            }
        )
        XCTAssertTrue(
            deliveredPrompts.contains { roleName, prompt, _ in
                roleName == "implementer" && prompt.contains("register_peer with name \"implementer\"")
            }
        )
    }
}
