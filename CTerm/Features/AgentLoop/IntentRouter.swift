// IntentRouter.swift
// CTerm
//
// Classifies a user's natural-language request into an intent category.
// Uses fast keyword matching first, falls back to LLM classification
// only when ambiguous. Feeds into PlanBuilder to determine execution strategy.

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.legato3.cterm", category: "IntentRouter")

enum GoalScope: String, Sendable {
    case project
    case workspace
    case system
    case browser
    case general

    var label: String {
        switch self {
        case .project: return "project"
        case .workspace: return "workspace"
        case .system: return "system"
        case .browser: return "browser"
        case .general: return "general"
        }
    }

    var includesProjectContext: Bool {
        self == .project
    }

    var includesWorkspaceContext: Bool {
        switch self {
        case .project, .workspace:
            return true
        case .system, .browser, .general:
            return false
        }
    }
}

// MARK: - Intent Category

enum IntentCategory: String, Sendable, CaseIterable {
    case explain          // "explain this output", "what does X mean"
    case generateCommand  // "how do I…", "give me a command to…"
    case executeCommand   // "run tests", "build the project", "deploy"
    case inspectRepo      // "show me the structure", "what files changed"
    case fixError         // "fix this error", "debug this failure"
    case runWorkflow      // "set up CI", "refactor module X", multi-step tasks
    case delegateToPeer   // "ask the reviewer to…", "tell the implementer…"
    case browserResearch  // "look up the docs for…", "check the release notes…"

    var label: String {
        switch self {
        case .explain:         return "Explain"
        case .generateCommand: return "Generate Command"
        case .executeCommand:  return "Execute Command"
        case .inspectRepo:     return "Inspect Repo"
        case .fixError:        return "Fix Error"
        case .runWorkflow:     return "Run Workflow"
        case .delegateToPeer:  return "Delegate to Peer"
        case .browserResearch: return "Browser Research"
        }
    }

    /// Whether this intent typically requires a multi-step plan.
    var needsPlan: Bool {
        switch self {
        case .explain, .generateCommand, .inspectRepo:
            return false
        case .executeCommand, .fixError, .runWorkflow, .delegateToPeer, .browserResearch:
            return true
        }
    }

    /// Default approval requirement for this intent type.
    var defaultApproval: ApprovalRequirement {
        switch self {
        case .explain, .generateCommand, .inspectRepo:
            return .none
        case .executeCommand:
            return .planLevel
        case .fixError, .runWorkflow:
            return .planLevel
        case .delegateToPeer:
            return .planLevel
        case .browserResearch:
            return .planLevel
        }
    }
}

// MARK: - Router

enum IntentRouter {

    // MARK: - Keyword Tables

    private static let explainKeywords: Set<String> = [
        "explain", "what does", "what is", "what are", "why did",
        "how does", "describe", "tell me about", "meaning of",
    ]

    private static let generateKeywords: Set<String> = [
        "give me a command", "how do i", "how to", "command for",
        "show me the command", "what command", "generate",
    ]

    private static let executeKeywords: Set<String> = [
        "run", "execute", "build", "test", "deploy", "install",
        "start", "stop", "restart", "compile", "lint", "format",
    ]

    private static let inspectKeywords: Set<String> = [
        "show me", "list", "what files", "structure", "find",
        "search", "where is", "status", "diff", "log", "history",
    ]

    private static let fixKeywords: Set<String> = [
        "fix", "debug", "resolve", "repair", "patch",
        "troubleshoot", "why is this failing", "error",
    ]

    private static let workflowKeywords: Set<String> = [
        "refactor", "migrate", "set up", "configure", "implement",
        "create", "add feature", "write", "redesign", "optimize",
    ]

    private static let delegateKeywords: Set<String> = [
        "ask the", "tell the", "delegate to", "have the",
        "orchestrator", "implementer", "reviewer", "send to",
    ]

    private static let browserResearchKeywords: Set<String> = [
        "look up", "check the docs", "release notes", "documentation",
        "browse", "open the page", "search the web", "api docs",
        "check the website", "read the page", "scrape", "inspect the site",
        "dashboard", "web form", "package docs", "changelog",
        "what version", "latest release", "npm page", "github page",
        "pypi", "crates.io", "docs.rs", "mdn", "stack overflow",
    ]

    private static let systemScopeKeywords: Set<String> = [
        "my mac", "this mac", "my machine", "this machine", "my computer", "this computer",
        "macos", "system", "cpu", "memory", "ram", "disk", "storage", "battery",
        "wifi", "network", "bluetooth", "kernel", "processes", "activity monitor",
    ]

    private static let projectScopeKeywords: Set<String> = [
        "git", "repo", "repository", "codebase", "project", "working tree", "branch",
        "commit", "diff", "pull request", "pr ", "tests", "test suite", "build",
        "compile", "lint", "module", "function", "class", "source", "xcode",
        "package.swift", "cargo", "npm", "swift package",
    ]

    private static let workspaceScopeKeywords: Set<String> = [
        "this folder", "this directory", "current directory", "current folder", "here",
        "pwd", "path", "list files", "find file", "find files", "show files",
    ]

    // MARK: - Classification

    nonisolated static func inferScope(_ input: String) -> GoalScope {
        let lower = input.lowercased()

        if browserResearchKeywords.contains(where: { lower.contains($0) }) {
            return .browser
        }

        if systemScopeKeywords.contains(where: { lower.contains($0) }) {
            return .system
        }

        let projectScore = score(lower, against: projectScopeKeywords)
        let workspaceScore = score(lower, against: workspaceScopeKeywords)

        if projectScore >= 0.2 {
            return .project
        }

        if workspaceScore >= 0.2 {
            return .workspace
        }

        return .general
    }

    /// Classify a user intent using fast keyword matching.
    /// Returns the best-matching category and a confidence score (0–1).
    static func classify(_ input: String, scope: GoalScope? = nil) -> (category: IntentCategory, confidence: Double) {
        let lower = input.lowercased()
        let resolvedScope = scope ?? inferScope(input)

        // Check for shell error context — strong signal for fixError
        if lower.contains("<latest_shell_error>") || lower.contains("fix this error") {
            return (.fixError, 0.95)
        }

        // Check for browser research signals
        if resolvedScope == .browser || browserResearchKeywords.contains(where: { lower.contains($0) }) {
            return (.browserResearch, 0.85)
        }

        // Check for peer delegation signals
        if delegateKeywords.contains(where: { lower.contains($0) }) {
            return (.delegateToPeer, 0.85)
        }

        // Score each category
        let scores: [(IntentCategory, Double)] = [
            (.explain,         score(lower, against: explainKeywords)),
            (.generateCommand, score(lower, against: generateKeywords)),
            (.executeCommand,  score(lower, against: executeKeywords)),
            (.inspectRepo,     score(lower, against: inspectKeywords)),
            (.fixError,        score(lower, against: fixKeywords)),
            (.runWorkflow,     score(lower, against: workflowKeywords)),
            (.browserResearch, score(lower, against: browserResearchKeywords)),
        ]

        let best = scores.max(by: { $0.1 < $1.1 })!

        // If confidence is too low, fall back based on scope rather than
        // assuming repo work in the current directory.
        if best.1 < 0.2 {
            let fallback = fallbackCategory(for: resolvedScope)
            logger.debug("IntentRouter: low confidence (\(best.1)), defaulting to \(fallback.rawValue) for \(resolvedScope.label) scope")
            return (fallback, 0.3)
        }

        logger.info("IntentRouter: classified as \(best.0.rawValue) (confidence: \(String(format: "%.2f", best.1)))")
        return best
    }

    /// Classify using LLM when keyword matching is ambiguous.
    /// Falls back to keyword classification on failure.
    static func classifyWithLLM(_ input: String, pwd: String?, scope: GoalScope? = nil) async -> IntentCategory {
        let resolvedScope = scope ?? inferScope(input)
        let prompt = """
        Classify this user request into exactly one category. Respond with only the category name.
        Categories: explain, generateCommand, executeCommand, inspectRepo, fixError, runWorkflow, delegateToPeer, browserResearch

        Scope: \(resolvedScope.label)
        Request: \(input.prefix(500))

        Category:
        """

        do {
            let result = try await OllamaCommandService.generateCommand(for: prompt, pwd: pwd)
            let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if let match = IntentCategory.allCases.first(where: { trimmed.contains($0.rawValue.lowercased()) }) {
                logger.info("IntentRouter (LLM): classified as \(match.rawValue)")
                return match
            }
        } catch {
            logger.debug("IntentRouter: LLM classification failed, using keyword fallback")
        }

        return classify(input, scope: resolvedScope).category
    }

    // MARK: - Scoring

    private static func fallbackCategory(for scope: GoalScope) -> IntentCategory {
        switch scope {
        case .browser:
            return .browserResearch
        case .system, .project:
            return .runWorkflow
        case .workspace:
            return .inspectRepo
        case .general:
            return .explain
        }
    }

    nonisolated private static func score(_ input: String, against keywords: Set<String>) -> Double {
        let matches = keywords.filter { input.contains($0) }
        guard !matches.isEmpty else { return 0 }
        // Weight by match length relative to input length
        let totalMatchLength = matches.reduce(0) { $0 + $1.count }
        let lengthScore = min(Double(totalMatchLength) / Double(input.count), 1.0)
        let countScore = min(Double(matches.count) / 3.0, 1.0)
        return (lengthScore * 0.4 + countScore * 0.6)
    }
}
