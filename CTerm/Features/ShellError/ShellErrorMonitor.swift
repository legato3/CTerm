// ShellErrorMonitor.swift
// CTerm
//
// Detects command failures from ghostty's COMMAND_FINISHED action.
// Called directly from handleCommandFinishedNotification — no polling.

import Foundation
import GhosttyKit
import OSLog

private let logger = Logger(subsystem: "com.legato3.cterm", category: "ShellErrorMonitor")

struct ShellErrorEvent: Identifiable, Sendable {
    let id: UUID
    let tabID: UUID
    let tabTitle: String
    let snippet: String
    let exitCode: Int
    let timestamp: Date

    init(tabID: UUID, tabTitle: String, snippet: String, exitCode: Int) {
        self.id = UUID()
        self.tabID = tabID
        self.tabTitle = tabTitle
        self.snippet = snippet
        self.exitCode = exitCode
        self.timestamp = Date()
    }
}

// Lines containing any of these strings are treated as error lines.
private let errorPatterns: [String] = [
    "error[E",          // Rust: error[E0308]
    "make: ***",        // Make build failure
    "❌",
    "Build failed",
    "Tests failed",
    "Test failed",
    "Command failed",
    "FAILED",
    "error:",           // Compiler errors (clang, swiftc, tsc, etc.)
    "Error:",           // Python, Node.js, Ruby, etc.
    "fatal:",           // git, gcc
    "Fatal:",
    "FAIL ",            // Jest, Go
    "Process exited with code [1-9]",
    "exit status [1-9]",
    "returned exit code [1-9]",
]

@MainActor
final class ShellErrorMonitor {
    private weak var tab: Tab?
    private static let cooldown: TimeInterval = 10.0
    private var lastCapturedAt: Date = .distantPast

    init(tab: Tab) {
        self.tab = tab
    }

    // Called by CTermWindowController from handleCommandFinishedNotification.
    // exitCode comes directly from ghostty — no heuristic prompt detection needed.
    func handleCommandFinished(exitCode: Int?, surface: ghostty_surface_t?) {
        guard let tab else { return }
        guard let exitCode, exitCode != 0 else { return }
        guard tab.lastShellError == nil else { return }
        guard Date().timeIntervalSince(lastCapturedAt) >= Self.cooldown else { return }

        let snippet = extractErrorSnippet(surface: surface) ?? "Exit code \(exitCode)"
        lastCapturedAt = Date()

        let event = ShellErrorEvent(
            tabID: tab.id,
            tabTitle: tab.title,
            snippet: snippet,
            exitCode: exitCode
        )
        tab.lastShellError = event
        logger.info("ShellError: exit \(exitCode) in \"\(tab.title)\": \(snippet.prefix(80))")
        NotificationCenter.default.post(
            name: .shellErrorCaptured,
            object: nil,
            userInfo: ["snippet": snippet, "tabTitle": tab.title]
        )
    }

    // MARK: - Snippet extraction

    private func extractErrorSnippet(surface: ghostty_surface_t?) -> String? {
        guard let surface,
              let text = GhosttyFFI.surfaceReadViewportText(surface) else { return nil }

        let lines = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let tail = Array(lines.suffix(25))

        // Drop the trailing prompt line if present (last line ending with common prompt chars).
        let body = tail.last.map { isPromptLine($0) } == true ? Array(tail.dropLast()) : tail
        let errorLines = body.filter { containsErrorPattern($0) }
        guard !errorLines.isEmpty else { return nil }
        return errorLines.suffix(8).joined(separator: "\n")
    }

    private func isPromptLine(_ line: String) -> Bool {
        let promptSuffixes = ["$ ", "% ", "❯ ", "➜ ", "> ", "λ ", "# "]
        return promptSuffixes.contains { line.hasSuffix($0) || line.contains($0) }
    }

    private func containsErrorPattern(_ line: String) -> Bool {
        errorPatterns.contains {
            line.range(of: $0, options: [.caseInsensitive, .regularExpression]) != nil
        }
    }
}
