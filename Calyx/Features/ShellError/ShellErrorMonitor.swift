// ShellErrorMonitor.swift
// Calyx
//
// Polls a tab's terminal surfaces for command failure signals.
// Stores the captured error on Tab.lastShellError for badge display and routing.

import Foundation
import GhosttyKit
import OSLog

private let logger = Logger(subsystem: "com.legato3.terminal", category: "ShellErrorMonitor")

struct ShellErrorEvent: Identifiable, Sendable {
    let id: UUID
    let tabID: UUID
    let tabTitle: String
    let snippet: String
    let timestamp: Date

    init(tabID: UUID, tabTitle: String, snippet: String) {
        self.id = UUID()
        self.tabID = tabID
        self.tabTitle = tabTitle
        self.snippet = snippet
        self.timestamp = Date()
    }
}

// Lines containing any of these strings are treated as error lines.
// Ordered from most specific to least to minimize false positives.
private let errorPatterns: [String] = [
    "error[E",          // Rust: error[E0308]
    "make: ***",        // Make build failure
    "❌",               // Test runners, scripts
    "Build failed",
    "Tests failed",
    "Test failed",
    "Command failed",
    "FAILED",
    "error:",           // Compiler errors (clang, swiftc, tsc, etc.)
    "Error:",           // Python, Node.js, Ruby, etc.
    "fatal:",           // git, gcc
    "Fatal:",
    "FAIL ",            // Jest: FAIL src/foo.test.js, Go: FAIL ./...
    "Process exited with code [1-9]",
    "exit status [1-9]",
    "returned exit code [1-9]",
]

// The last non-empty line must look like a shell prompt — confirms the command finished.
private let promptSuffixes: [String] = [
    "$ ", "% ", "❯ ", "➜ ", "> ", "λ ", "# "
]

@MainActor
final class ShellErrorMonitor {
    private weak var tab: Tab?
    private var pollTask: Task<Void, Never>?
    private var lastCapturedAt: Date = .distantPast

    private static let cooldown: TimeInterval = 10.0
    private static let pollInterval: UInt64 = 800_000_000 // 800 ms

    init(tab: Tab) {
        self.tab = tab
    }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(nanoseconds: Self.pollInterval)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func tick() {
        guard let tab else { stop(); return }
        // Don't recapture during cooldown or while an unrouted error is pending.
        guard Date().timeIntervalSince(lastCapturedAt) >= Self.cooldown else { return }
        guard tab.lastShellError == nil else { return }

        for surfaceID in tab.registry.allIDs {
            guard let controller = tab.registry.controller(for: surfaceID),
                  let surface = controller.surface,
                  let text = GhosttyFFI.surfaceReadViewportText(surface) else { continue }

            let lines = text.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            let tail = Array(lines.suffix(25))

            if let snippet = extractError(from: tail) {
                lastCapturedAt = Date()
                let event = ShellErrorEvent(tabID: tab.id, tabTitle: tab.title, snippet: snippet)
                tab.lastShellError = event
                logger.info("ShellError: captured in \"\(tab.title)\": \(snippet.prefix(80))")
                NotificationCenter.default.post(
                    name: .shellErrorCaptured,
                    object: nil,
                    userInfo: ["snippet": snippet, "tabTitle": tab.title]
                )
                return
            }
        }
    }

    // MARK: - Detection

    private func extractError(from lines: [String]) -> String? {
        guard lines.count >= 2 else { return nil }

        // Last line must look like a shell prompt — the command has exited.
        guard isPromptLine(lines.last!) else { return nil }

        // Gather error lines from everything except the trailing prompt.
        let body = lines.dropLast()
        let errorLines = body.filter { containsErrorPattern($0) }
        guard !errorLines.isEmpty else { return nil }

        // Return the last few error lines as the snippet (cap at 8).
        return errorLines.suffix(8).joined(separator: "\n")
    }

    private func isPromptLine(_ line: String) -> Bool {
        promptSuffixes.contains { line.hasSuffix($0) || line.contains($0) }
    }

    private func containsErrorPattern(_ line: String) -> Bool {
        errorPatterns.contains { line.range(of: $0, options: [.caseInsensitive, .regularExpression]) != nil }
    }
}
