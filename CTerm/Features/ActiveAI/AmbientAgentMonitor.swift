// AmbientAgentMonitor.swift
// CTerm
//
// Phase 3: Background monitor that watches terminal output and proactively
// offers to fix build errors, run tests after file changes, or suggest
// git operations when dirty file count is high.
//
// Surfaces as a subtle notification dot on the agent input bar — never modal.
// Opt-in via AppStorageKeys.ambientAgentEnabled.

import Foundation
import OSLog
import Observation

private let logger = Logger(subsystem: "com.legato3.cterm", category: "AmbientAgent")

// MARK: - Ambient Suggestion

struct AmbientSuggestion: Identifiable, Sendable {
    let id: UUID
    let kind: Kind
    let title: String
    let prompt: String
    let icon: String
    let createdAt: Date

    enum Kind: String, Sendable {
        case fixBuildError
        case runTests
        case gitCommit
        case gitStash
    }

    init(kind: Kind, title: String, prompt: String, icon: String) {
        self.id = UUID()
        self.kind = kind
        self.title = title
        self.prompt = prompt
        self.icon = icon
        self.createdAt = Date()
    }
}

// MARK: - Monitor

@Observable
@MainActor
final class AmbientAgentMonitor {
    static let shared = AmbientAgentMonitor()

    /// Current ambient suggestions. Cleared when acted upon or dismissed.
    private(set) var suggestions: [AmbientSuggestion] = []

    /// True when there are unread ambient suggestions.
    var hasSuggestions: Bool { !suggestions.isEmpty }

    private var pollTask: Task<Void, Never>?
    private var lastErrorCheckAt: Date = .distantPast
    private var lastGitCheckAt: Date = .distantPast
    private var errorObserver: NSObjectProtocol?

    private static let pollInterval: UInt64 = 15_000_000_000 // 15s
    private static let errorCooldown: TimeInterval = 30
    private static let gitCooldown: TimeInterval = 60
    private static let dirtyFileThreshold = 8

    private init() {}

    // MARK: - Lifecycle

    func start() {
        guard pollTask == nil else { return }
        guard UserDefaults.standard.bool(forKey: AppStorageKeys.ambientAgentEnabled) else { return }

        // Listen for shell errors to proactively suggest fixes
        errorObserver = NotificationCenter.default.addObserver(
            forName: .shellErrorCaptured,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let snippet = note.userInfo?["snippet"] as? String ?? ""
            let tab = note.userInfo?["tabTitle"] as? String ?? ""
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard Date().timeIntervalSince(self.lastErrorCheckAt) >= Self.errorCooldown else { return }
                self.lastErrorCheckAt = Date()

                guard !snippet.isEmpty else { return }

                // Only suggest if it looks like a build/compile error
                let buildPatterns = ["error:", "Error:", "Build failed", "FAILED", "fatal error:"]
                guard buildPatterns.contains(where: { snippet.contains($0) }) else { return }

                let suggestion = AmbientSuggestion(
                    kind: .fixBuildError,
                    title: "Build error in \(tab)",
                    prompt: "Fix this build error: \(snippet.prefix(200))",
                    icon: "wrench.and.screwdriver"
                )
                self.addSuggestion(suggestion)
            }
        }

        // Periodic git status check
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.pollInterval)
                self?.checkGitStatus()
            }
        }

        logger.info("AmbientAgentMonitor started")
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        if let observer = errorObserver {
            NotificationCenter.default.removeObserver(observer)
            errorObserver = nil
        }
    }

    func dismiss(id: UUID) {
        suggestions.removeAll { $0.id == id }
    }

    func dismissAll() {
        suggestions.removeAll()
    }

    func actOn(_ suggestion: AmbientSuggestion) {
        suggestions.removeAll { $0.id == suggestion.id }
    }

    // MARK: - Git Status Check

    private func checkGitStatus() {
        guard UserDefaults.standard.bool(forKey: AppStorageKeys.ambientAgentEnabled) else { return }
        guard Date().timeIntervalSince(lastGitCheckAt) >= Self.gitCooldown else { return }
        lastGitCheckAt = Date()

        guard let pwd = TerminalControlBridge.shared.delegate?.activeTabPwd else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let dirtyFiles = await self.countDirtyFiles(pwd: pwd)

            // Already have a git suggestion? Don't pile on.
            guard !self.suggestions.contains(where: { $0.kind == .gitCommit || $0.kind == .gitStash }) else { return }

            if dirtyFiles >= Self.dirtyFileThreshold {
                let suggestion = AmbientSuggestion(
                    kind: .gitCommit,
                    title: "\(dirtyFiles) uncommitted files",
                    prompt: "Stage and commit the \(dirtyFiles) dirty files with a descriptive message",
                    icon: "arrow.triangle.branch"
                )
                self.addSuggestion(suggestion)
            }
        }
    }

    private func countDirtyFiles(pwd: String) async -> Int {
        guard let output = await TerminalContextGatherer.runTool(
            "git", args: ["status", "--porcelain"], cwd: pwd, timeout: 3
        ) else { return 0 }
        return output.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .count
    }

    // MARK: - Helpers

    private func addSuggestion(_ suggestion: AmbientSuggestion) {
        // Deduplicate by kind
        guard !suggestions.contains(where: { $0.kind == suggestion.kind }) else { return }
        suggestions.append(suggestion)
        // Cap at 3 ambient suggestions
        if suggestions.count > 3 {
            suggestions = Array(suggestions.suffix(3))
        }
        logger.debug("Ambient suggestion: \(suggestion.title)")
    }
}
