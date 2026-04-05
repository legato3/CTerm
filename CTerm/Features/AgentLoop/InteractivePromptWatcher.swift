// InteractivePromptWatcher.swift
// CTerm
//
// Watches a GhosttySurface's viewport for interactive prompts (y/N, password,
// press RETURN, etc.) while an agent-driven shell step is running. When a
// prompt is detected, fires an onMatch callback so ExecutionCoordinator can
// route through ApprovalGate + ApprovalSheet instead of letting the agent
// deadlock on stdin.
//
// Matching is anchored to the *end* of the last non-empty viewport line so
// that prompt-like text mid-output does not trigger a false positive.

import Foundation
import OSLog
import GhosttyKit

private let logger = Logger(subsystem: "com.legato3.cterm", category: "InteractivePromptWatcher")

@MainActor
final class InteractivePromptWatcher {

    // MARK: - Pattern

    struct Pattern: Sendable {
        let id: String               // "yes_no", "password", "press_return", etc.
        let regex: NSRegularExpression
        let defaultResponse: String? // e.g. "\n" for press-return. nil => user must choose
        let isSensitive: Bool        // true => never pre-approve (passwords)
        let displayLabel: String     // shown in approval sheet
    }

    // MARK: - Curated patterns

    /// Curated pattern list. Each regex is anchored to end-of-line so that
    /// prompt-like text mid-output (e.g. "Overwrite? (y/n)" inside a doc)
    /// does not fire while the program has moved past it.
    static let patterns: [Pattern] = {
        func make(_ id: String, _ pattern: String, default def: String?, sensitive: Bool, label: String) -> Pattern? {
            guard let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive]
            ) else {
                return nil
            }
            return Pattern(
                id: id,
                regex: regex,
                defaultResponse: def,
                isSensitive: sensitive,
                displayLabel: label
            )
        }

        var result: [Pattern] = []

        // Order matters — more specific patterns must come first so that
        // a line like "Continue? [y/N]" matches `continue_confirm` rather
        // than the generic `yes_no` fallback.

        // Password prompts. Sensitive — never pre-approved.
        if let p = make(
            "password",
            #"([Pp]assword(?:\s+for\s+.+)?|[Pp]assphrase(?:\s+for\s+.+)?)\s*:\s*\$?\s*$"#,
            default: nil,
            sensitive: true,
            label: "Password / passphrase"
        ) { result.append(p) }

        // Press RETURN / ENTER / any key to continue.
        if let p = make(
            "press_return",
            #"[Pp]ress\s+(RETURN|ENTER|<RETURN>|<ENTER>|any key)[^$]*\$?\s*$"#,
            default: "\n",
            sensitive: false,
            label: "Press RETURN / any key"
        ) { result.append(p) }

        // Are you sure? (yes/no)
        if let p = make(
            "are_you_sure",
            #"[Aa]re you sure\??\s*(\(yes/no\)|\[[yY]/[nN]\])?\s*[:?]?\s*\$?\s*$"#,
            default: nil,
            sensitive: false,
            label: "Are you sure?"
        ) { result.append(p) }

        // Overwrite? (y/N)
        if let p = make(
            "overwrite",
            #"[Oo]verwrite\??\s*(\[[yY]/[nN]\]|\([yY]/[nN]\))?\s*[:?]?\s*\$?\s*$"#,
            default: nil,
            sensitive: false,
            label: "Overwrite?"
        ) { result.append(p) }

        // Continue? [Y/n]
        if let p = make(
            "continue_confirm",
            #"[Cc]ontinue\??\s*(\[[yY]/[nN]\]|\([yY]/[nN]\))?\s*[:?]?\s*\$?\s*$"#,
            default: nil,
            sensitive: false,
            label: "Continue?"
        ) { result.append(p) }

        // Generic y/N, Y/n, y/n bracketed prompts — fallback, end-anchored.
        if let p = make(
            "yes_no",
            #"(\[[yY]/[nN]\]|\([yY]/[nN]\))\s*[:?]?\s*\$?\s*$"#,
            default: nil,
            sensitive: false,
            label: "Yes / No prompt"
        ) { result.append(p) }

        // (yes/no)?
        if let p = make(
            "yes_no_word",
            #"\(yes/no\)\??\s*[:?]?\s*\$?\s*$"#,
            default: nil,
            sensitive: false,
            label: "yes / no prompt"
        ) { result.append(p) }

        return result
    }()

    // MARK: - Viewport provider

    /// Returns the current viewport text as a string. Called on each poll.
    typealias ViewportProvider = @MainActor () -> String?

    // MARK: - Stored properties

    let stepID: UUID
    private let viewportProvider: ViewportProvider
    private let pollInterval: TimeInterval
    private let onMatch: @MainActor (Pattern, String) async -> Void
    private var task: Task<Void, Never>?
    private var lastFiredHash: Int?
    /// After a sensitive/password prompt fires, pause polling for this long
    /// to avoid spamming approvals while the user types in the terminal.
    private var suppressUntil: Date?

    // MARK: - Init

    init(
        stepID: UUID,
        pollInterval: TimeInterval = 0.75,
        viewportProvider: @escaping ViewportProvider,
        onMatch: @escaping @MainActor (Pattern, String) async -> Void
    ) {
        self.stepID = stepID
        self.pollInterval = pollInterval
        self.viewportProvider = viewportProvider
        self.onMatch = onMatch
    }

    // MARK: - Lifecycle

    func start() {
        stop() // idempotent
        let interval = pollInterval
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            let nanos = UInt64(max(0.1, interval) * 1_000_000_000)
            while !Task.isCancelled {
                self.tick()
                try? await Task.sleep(nanoseconds: nanos)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// Clear the post-fire suppression window. Used when a sensitive prompt
    /// was handled inline via the secure-input sheet — we don't need to wait
    /// 30s because the user never touched the terminal.
    func clearSuppression() {
        suppressUntil = nil
    }

    deinit {
        task?.cancel()
    }

    // MARK: - Poll tick

    private func tick() {
        // Respect suppression window (e.g. after password prompt).
        if let until = suppressUntil, Date() < until {
            return
        } else if suppressUntil != nil {
            suppressUntil = nil
        }

        guard let text = viewportProvider() else { return }
        let lines = Self.trailingNonEmptyLines(text, count: 4)
        guard let (pattern, matchedLine) = Self.match(lines: lines) else { return }

        // Debounce on (pattern.id, last-line).
        let hash = Self.hashFor(patternID: pattern.id, line: matchedLine)
        if hash == lastFiredHash { return }
        lastFiredHash = hash

        // Sensitive prompts install a 30-second suppression window after
        // firing so we don't spam approvals while the user types a password
        // into the terminal directly.
        if pattern.isSensitive {
            suppressUntil = Date().addingTimeInterval(30)
        }

        let capturedPattern = pattern
        let capturedLine = matchedLine
        let handler = onMatch
        Task { @MainActor in
            await handler(capturedPattern, capturedLine)
        }
    }

    // MARK: - Matching (exposed for tests)

    /// Take the last `count` non-empty trimmed lines of `text`.
    static func trailingNonEmptyLines(_ text: String, count: Int) -> [String] {
        let all = text
            .components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if all.count <= count { return all }
        return Array(all.suffix(count))
    }

    /// Match the patterns against the trailing last line only — patterns are
    /// anchored to end-of-buffer. Returns the first matching pattern along
    /// with the line that matched.
    static func match(lines: [String]) -> (Pattern, String)? {
        guard let last = lines.last, !last.isEmpty else { return nil }
        let range = NSRange(last.startIndex..<last.endIndex, in: last)
        for pattern in patterns {
            if pattern.regex.firstMatch(in: last, options: [], range: range) != nil {
                return (pattern, last)
            }
        }
        return nil
    }

    /// Convenience for tests + debouncing.
    static func hashFor(patternID: String, line: String) -> Int {
        var hasher = Hasher()
        hasher.combine(patternID)
        hasher.combine(line)
        return hasher.finalize()
    }
}
