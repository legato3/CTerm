// SlashCommandRegistry.swift
// CTerm
//
// Static registry of built-in slash commands. v1 is built-in-only; no
// user-extensible registry. Each command has a concrete prompt template
// that is rendered against the user's invocation and dispatched to the
// agent via AgentSessionRouter.

import Foundation

@MainActor
enum SlashCommandRegistry {

    static let builtIn: [SlashCommand] = [
        SlashCommand(
            name: "review",
            description: "Review uncommitted changes, summarize risks",
            args: [],
            template: { _ in
                "Review all uncommitted changes in the current repository. Identify risks, regressions, and test gaps. Return a bulleted summary grouped by file."
            },
            enrichContext: true
        ),
        SlashCommand(
            name: "explain",
            description: "Explain a file's purpose + structure",
            args: [SlashArg(name: "file", kind: .file, required: true)],
            template: { inv in
                let file = inv.args.first ?? "<unspecified>"
                return "Read \(file) and explain its purpose, key types, and how it fits into the codebase. Return a concise structured summary (purpose → public API → key collaborators → notable edge cases)."
            },
            enrichContext: true
        ),
        SlashCommand(
            name: "plan",
            description: "Produce a multi-step plan without executing",
            args: [SlashArg(name: "goal", kind: .text, required: true)],
            template: { inv in
                let goal = inv.args.joined(separator: " ")
                let target = goal.isEmpty ? "<goal>" : goal
                return "Produce a multi-step implementation plan for: \(target). Do not execute any steps — only return the numbered plan with brief rationale per step and any open questions."
            },
            enrichContext: true
        ),
        SlashCommand(
            name: "fix",
            description: "Read the latest shell error and propose a fix",
            args: [],
            template: { _ in
                "Read the most recent failed command in the terminal and propose a concrete fix. Explain the root cause briefly, then list the corrective commands to run."
            },
            enrichContext: true
        ),
        SlashCommand(
            name: "test",
            description: "Run relevant tests and triage failures",
            args: [],
            template: { _ in
                "Run the tests relevant to the recent changes. If any fail, triage the failures: group by root cause, propose fixes, and indicate which tests should be re-run first."
            },
            enrichContext: true
        ),
        SlashCommand(
            name: "commit",
            description: "Stage and write a commit message from the diff",
            args: [],
            template: { _ in
                "Review the uncommitted changes, stage the appropriate files, and write a concise commit message that explains the why (not just the what). Show the proposed message before committing."
            },
            enrichContext: true
        ),
        SlashCommand(
            name: "simplify",
            description: "Refactor for clarity without behavior change",
            args: [SlashArg(name: "file", kind: .file, required: true)],
            template: { inv in
                let file = inv.args.first ?? "<unspecified>"
                return "Refactor \(file) for clarity. Preserve behavior exactly. Focus on naming, small function extraction, removing redundancy, and reducing nesting. Summarize the changes afterward."
            },
            enrichContext: true
        ),
        SlashCommand(
            name: "refactor",
            description: "Deeper structural refactor",
            args: [SlashArg(name: "file", kind: .file, required: true)],
            template: { inv in
                let file = inv.args.first ?? "<unspecified>"
                return "Propose and apply a deeper structural refactor for \(file). Identify responsibilities that should be split out, decoupling opportunities, and type-level improvements. Preserve public behavior; update call sites as needed."
            },
            enrichContext: true
        ),
        SlashCommand(
            name: "docs",
            description: "Add or update doc comments",
            args: [SlashArg(name: "file", kind: .file, required: true)],
            template: { inv in
                let file = inv.args.first ?? "<unspecified>"
                return "Add or update documentation comments in \(file). Cover public types and methods, explain non-obvious behavior, and note invariants. Keep comments concise and match the existing doc style."
            },
            enrichContext: true
        ),
    ]

    /// Case-sensitive exact lookup by command name (without the leading slash).
    static func lookup(name: String) -> SlashCommand? {
        builtIn.first { $0.name == name }
    }

    /// Commands whose `name` starts with `query` (case-insensitive). Empty
    /// query returns all commands.
    static func matching(query: String) -> [SlashCommand] {
        guard !query.isEmpty else { return builtIn }
        let needle = query.lowercased()
        return builtIn.filter { $0.name.lowercased().hasPrefix(needle) }
    }
}
