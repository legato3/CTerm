// SlashCommand.swift
// CTerm
//
// Model types for the built-in slash-command palette. Slash commands are
// triggered by typing "/" at the start of the compose bar draft. Each
// command carries a prompt template that is rendered with user-supplied
// args and dispatched through AgentSessionRouter.

import Foundation

@MainActor
struct SlashArg: Hashable, Sendable {
    enum Kind: Sendable, Hashable {
        case file
        case text
        case diff
        case selection
    }

    let name: String
    let kind: Kind
    let required: Bool
}

@MainActor
struct SlashCommand: Identifiable, Hashable {
    let name: String
    let description: String
    let args: [SlashArg]
    let template: @MainActor (SlashCommandInvocation) -> String
    let enrichContext: Bool

    nonisolated var id: String { name }

    /// Human-readable signature, e.g. `/explain <file>`.
    var signature: String {
        "/" + name + args.map { " <\($0.name)>" }.joined()
    }

    /// At least one required arg.
    var requiresArg: Bool {
        args.contains { $0.required }
    }

    // MARK: - Hashable / Equatable
    // We intentionally ignore the closure; identity flows through `name`.

    nonisolated static func == (lhs: SlashCommand, rhs: SlashCommand) -> Bool {
        lhs.name == rhs.name
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

@MainActor
struct SlashCommandInvocation: Hashable {
    let command: SlashCommand
    let args: [String]

    /// Reconstructs the raw slash string as the user would have typed it.
    var raw: String {
        "/" + command.name + (args.isEmpty ? "" : " " + args.joined(separator: " "))
    }

    /// Rendered prompt ready for the agent.
    var renderedPrompt: String {
        command.template(self)
    }
}
