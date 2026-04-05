// ShellTitleParser.swift
// CTerm
//
// Interprets SET_TITLE events from ghostty's shell-integration-features=title.
//
// When shell integration is active, ghostty sets the window title to the
// running command text during preexec (OSC 133;C), then resets it to the
// shell name (e.g. "zsh", "bash") on precmd (OSC 133;A).
//
// This lets us open a TerminalCommandBlock with the real command text —
// the same mechanism Warp uses to track discrete command units.

import Foundation

enum ShellTitleParser {

    // Shell names that ghostty resets the title to on precmd.
    // When we see one of these, a command just finished (COMMAND_FINISHED follows).
    private static let knownShells: Set<String> = [
        "zsh", "bash", "fish", "sh", "dash", "ksh", "tcsh", "csh",
        "nu", "elvish", "pwsh", "powershell",
    ]

    // Titles that are clearly app/session names, not commands.
    // Ghostty may also set these from the user's `title` config key.
    private static let ignoredPrefixes: [String] = [
        "CTerm", "Terminal", "ssh ", "tmux", "screen",
    ]

    /// Returns true when the title represents a running command (preexec fired).
    /// Returns false when it's a shell-reset title (precmd fired) or an app name.
    static func isRunningCommand(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }

        // Shell name reset — precmd fired, not a new command.
        if knownShells.contains(trimmed.lowercased()) { return false }

        // App/session name — not a shell command.
        if ignoredPrefixes.contains(where: { trimmed.hasPrefix($0) }) { return false }

        // Looks like a command invocation.
        return true
    }

    /// Extracts the command text from a title set by shell integration.
    /// Ghostty's title feature sets the title to exactly the command string,
    /// so no stripping is needed — return as-is.
    static func extractCommand(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespaces)
    }
}
