// HardStopGuard.swift
// CTerm
//
// Absolute-no-autoapprove list. Commands matched here ALWAYS surface the
// approval sheet, regardless of granted scope or trust mode. The user can
// only approve them `.once` — scope picker is disabled for hard-stops.

import Foundation

enum HardStopReason: String, Sendable, Codable {
    case deleteRoot
    case forcePushProtected
    case hardResetProtected
    case sudoDestructive
    case bypassHooks

    var headline: String {
        switch self {
        case .deleteRoot:           return "Deletes from root or home directory"
        case .forcePushProtected:   return "Force-push to a protected branch"
        case .hardResetProtected:   return "Hard reset on a protected branch"
        case .sudoDestructive:      return "Privileged destructive command"
        case .bypassHooks:          return "Bypasses commit / signing hooks"
        }
    }

    var detail: String {
        switch self {
        case .deleteRoot:           return "Can wipe out your files with no undo."
        case .forcePushProtected:   return "Overwrites remote history for a shared branch."
        case .hardResetProtected:   return "Discards commits on a shared branch."
        case .sudoDestructive:      return "Runs with elevated privileges and may be irreversible."
        case .bypassHooks:          return "Skips safety checks the team has put in place."
        }
    }
}

enum HardStopGuard {

    private static let protectedBranches: Set<String> = [
        "main", "master", "trunk", "develop", "production", "release",
    ]

    static func isHardStop(_ command: String, gitBranch: String? = nil) -> HardStopReason? {
        let lower = command.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lower.isEmpty else { return nil }

        // rm -rf /  or  rm -rf ~  or rm -rf $HOME
        if lower.contains("rm ") && containsDestructiveFlag(lower) {
            if lower.contains(" /") || lower.contains(" ~") || lower.contains(" $home") || lower.hasSuffix(" /") || lower.hasSuffix(" ~") {
                return .deleteRoot
            }
            // sudo rm -rf anything is always hard-stopped
            if lower.hasPrefix("sudo ") { return .sudoDestructive }
        }

        // sudo dd  /  sudo mkfs  /  sudo chmod -R on root
        if lower.hasPrefix("sudo ") {
            if lower.contains(" dd ") || lower.contains(" mkfs") || lower.contains("chmod -r /") || lower.contains("chown -r /") {
                return .sudoDestructive
            }
        }

        // git push --force(-with-lease) to protected branch
        if lower.contains("git push") && (lower.contains("--force") || lower.contains(" -f") || lower.contains("--force-with-lease")) {
            if mentionsProtectedBranch(lower, currentBranch: gitBranch) {
                return .forcePushProtected
            }
        }

        // git reset --hard on protected branch
        if lower.contains("git reset") && lower.contains("--hard") {
            if isOnProtectedBranch(gitBranch) || mentionsProtectedBranch(lower, currentBranch: gitBranch) {
                return .hardResetProtected
            }
        }

        // --no-verify / -n on git commit/push, or commit.gpgsign=false
        if (lower.contains("git commit") || lower.contains("git push")) && lower.contains("--no-verify") {
            return .bypassHooks
        }
        if lower.contains("commit.gpgsign=false") || lower.contains("commit.gpgsign=0") {
            return .bypassHooks
        }

        return nil
    }

    // MARK: - Helpers

    private static func containsDestructiveFlag(_ lower: String) -> Bool {
        lower.contains("-rf") || lower.contains("-fr") || lower.contains(" -r ") && lower.contains(" -f")
    }

    private static func mentionsProtectedBranch(_ lower: String, currentBranch: String?) -> Bool {
        for branch in protectedBranches {
            if lower.contains(" \(branch)") || lower.hasSuffix(" \(branch)") {
                return true
            }
        }
        if lower.contains("release/") { return true }
        // if no explicit ref, treat current branch as the push target
        if !lower.contains(" origin ") && !lower.contains(" upstream ") {
            return isOnProtectedBranch(currentBranch)
        }
        return false
    }

    private static func isOnProtectedBranch(_ branch: String?) -> Bool {
        guard let branch else { return false }
        let b = branch.lowercased()
        if protectedBranches.contains(b) { return true }
        if b.hasPrefix("release/") { return true }
        return false
    }
}
