// AgentWorkflow.swift
// CTerm
//
// Templates for coordinated multi-agent Claude sessions.

import Foundation

struct WorkflowLaunchParams: Sendable {
    let workflow: AgentWorkflow
    let autoStart: Bool
    let sessionName: String
    let initialTask: String
    let runtime: AgentRuntimeConfiguration
}

struct AgentRole: Identifiable, Sendable {
    let id: UUID
    var name: String
    let description: String

    init(name: String, description: String) {
        self.id = UUID()
        self.name = name
        self.description = description
    }
}

struct AgentWorkflow: Identifiable, Sendable {
    let id: UUID
    let name: String
    let icon: String
    let description: String
    let roles: [AgentRole]

    init(name: String, icon: String, description: String, roles: [AgentRole]) {
        self.id = UUID()
        self.name = name
        self.icon = icon
        self.description = description
        self.roles = roles
    }

    // MARK: - Role Prompt

    /// Generates the startup context message for a given role in a session.
    /// Shared by CTermWindowController (terminal injection) and IPCAgentsView (MCP send_message).
    static func rolePrompt(
        roleName: String,
        allRoles: [String],
        runtime: AgentRuntimeConfiguration,
        port: Int,
        initialTask: String = ""
    ) -> String {
        let teammates = allRoles.filter { $0.lowercased() != roleName.lowercased() }
        let teammatesStr = teammates.isEmpty
            ? "no other agents in this session"
            : teammates.map { "\"\($0)\"" }.joined(separator: " and ")

        let roleContext: String
        switch roleName.lowercased() {
        case "orchestrator", "planner":
            roleContext = "You are the \(roleName.uppercased()). Your job is to plan the work, break it into concrete tasks, and delegate to your teammates using delegate_task. Use group_id to fan out parallel tasks and get_aggregated_result to collect results."
        case "implementer", "coder":
            roleContext = "You are the \(roleName.uppercased()). Your job is to write and edit code as directed. When you receive a delegation, do the work and call report_result with the task_id when done."
        case "reviewer":
            roleContext = "You are the REVIEWER. Your job is to review code and give structured feedback. When you receive a delegation, review the code and call report_result with your findings."
        case "researcher":
            roleContext = "You are the RESEARCHER. Your job is to browse documentation, search for solutions, and gather context. When you receive a delegation, research the topic and call report_result with your findings."
        case "tester":
            roleContext = "You are the TESTER. Your job is to run tests, analyze failures, and report results. When you receive a delegation, run the relevant tests and call report_result with pass/fail results."
        default:
            roleContext = "You are the \(roleName.uppercased()) agent."
        }

        let taskSuffix = initialTask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ""
            : "\n\nInitial task:\n\(initialTask)"

        if runtime.registersWithIPC {
            return """
            \(roleContext) Your teammates are: \(teammatesStr). \
            You are running inside CTerm using \(runtime.displayName). \
            The CTerm IPC MCP server is running on port \(port) — use the cterm-ipc MCP tools to communicate with your team. \
            Start by calling register_peer with name "\(roleName)" and role "\(roleName)", \
            then list_peers to see who is connected, and coordinate from there.\(taskSuffix)
            """
        }

        return """
        \(roleContext) Your teammates are: \(teammatesStr). \
        You are running as an Ollama-backed/local AI agent inside CTerm via \(runtime.displayName). \
        This runtime does not have CTerm MCP tools, so stay focused on the task in this tab and respond directly in the terminal. \
        When you suggest commands, format them as executable shell commands.\(taskSuffix)
        """
    }

    static func rolePrompt(roleName: String, allRoles: [String], port: Int) -> String {
        rolePrompt(
            roleName: roleName,
            allRoles: allRoles,
            runtime: .default,
            port: port
        )
    }

    static let templates: [AgentWorkflow] = [
        AgentWorkflow(
            name: "Solo",
            icon: "person",
            description: "One agent for a single focused task",
            roles: [
                AgentRole(name: "agent", description: "Single Claude agent"),
            ]
        ),
        AgentWorkflow(
            name: "Pair",
            icon: "person.2",
            description: "Orchestrator plans while implementer codes",
            roles: [
                AgentRole(name: "orchestrator", description: "Plans and delegates tasks"),
                AgentRole(name: "implementer", description: "Writes and edits code"),
            ]
        ),
        AgentWorkflow(
            name: "Team",
            icon: "person.3",
            description: "Full loop: plan, implement, and review",
            roles: [
                AgentRole(name: "orchestrator", description: "Plans and delegates tasks"),
                AgentRole(name: "implementer", description: "Writes and edits code"),
                AgentRole(name: "reviewer", description: "Reviews and gives feedback"),
            ]
        ),
        AgentWorkflow(
            name: "Full Squad",
            icon: "person.3.sequence",
            description: "Planner, coder, reviewer, browser research, and test runner",
            roles: [
                AgentRole(name: "planner", description: "Breaks down goals into delegated sub-tasks"),
                AgentRole(name: "coder", description: "Implements code changes"),
                AgentRole(name: "reviewer", description: "Reviews code and gives structured feedback"),
                AgentRole(name: "researcher", description: "Browses docs and gathers context"),
                AgentRole(name: "tester", description: "Runs tests and reports results"),
            ]
        ),
    ]
}
