// ProjectContextProvider.swift
// Calyx
//
// Gathers live project context for ambient injection into new agent sessions.
// All operations are synchronous and fast (<50ms typical) — safe to call from
// background MCP handler threads.

import Foundation

enum ProjectContextProvider {

    // MARK: - Public API

    /// Build a context dictionary for the given working directory.
    /// Includes: CLAUDE.md, git branch, recent commits, dirty files,
    /// agent memories, failing tests, and active peers.
    static func gather(workDir: String) -> [String: Any] {
        let gitRoot = gitOutput(["-C", workDir, "rev-parse", "--show-toplevel"], in: workDir)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let root = gitRoot ?? workDir

        var ctx: [String: Any] = ["cwd": workDir]

        // CLAUDE.md — look at git root first, then cwd
        if let md = readFile(atPath: "\(root)/CLAUDE.md") ?? readFile(atPath: "\(workDir)/CLAUDE.md") {
            ctx["claude_md"] = md
        }

        // Git metadata
        if let branch = gitOutput(["-C", workDir, "branch", "--show-current"], in: workDir)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !branch.isEmpty {
            ctx["branch"] = branch
        }

        let commits = gitOutput(["-C", workDir, "log", "--oneline", "-5"], in: workDir)?
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
        if !commits.isEmpty { ctx["recent_commits"] = commits }

        // Dirty files: staged + unstaged, deduplicated
        let staged = gitOutput(["-C", workDir, "diff", "--name-only", "--cached"], in: workDir)?
            .components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } ?? []
        let unstaged = gitOutput(["-C", workDir, "diff", "--name-only"], in: workDir)?
            .components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } ?? []
        let dirty = Array(Set(staged + unstaged)).sorted()
        if !dirty.isEmpty { ctx["dirty_files"] = dirty }

        // Agent memories for this project
        let projectKey = AgentMemoryStore.key(for: workDir)
        let memories = AgentMemoryStore.shared.listAll(projectKey: projectKey)
        if !memories.isEmpty {
            ctx["memories"] = memories.map { ["key": $0.key, "value": $0.value] }
        }

        // Failing tests (main-actor read) — use Sendable [String] to cross isolation.
        var failureNames: [String] = []
        DispatchQueue.main.sync {
            failureNames = TestRunnerStore.shared.failures.map(\.name)
        }
        if !failureNames.isEmpty { ctx["failing_tests"] = failureNames }

        // Active peers (main-actor read via IPCAgentState mirror).
        var peerPairs: [[String: String]] = []
        DispatchQueue.main.sync {
            peerPairs = IPCAgentState.shared.peers.map { ["name": $0.name, "role": $0.role] }
        }
        if !peerPairs.isEmpty { ctx["active_peers"] = peerPairs }

        return ctx
    }

    // MARK: - Formatted prompt block

    /// Returns a human-readable context block suitable for prepending to a prompt.
    static func formattedBlock(for workDir: String) -> String {
        let ctx = gather(workDir: workDir)
        var lines: [String] = ["<calyx_project_context>"]

        if let cwd = ctx["cwd"] as? String { lines.append("cwd: \(cwd)") }
        if let branch = ctx["branch"] as? String { lines.append("branch: \(branch)") }

        if let commits = ctx["recent_commits"] as? [String], !commits.isEmpty {
            lines.append("recent_commits:")
            commits.forEach { lines.append("  \($0)") }
        }

        if let dirty = ctx["dirty_files"] as? [String], !dirty.isEmpty {
            lines.append("dirty_files: \(dirty.joined(separator: ", "))")
        }

        if let memories = ctx["memories"] as? [[String: Any]], !memories.isEmpty {
            lines.append("memories:")
            memories.forEach { m in
                if let k = m["key"] as? String, let v = m["value"] as? String {
                    lines.append("  \(k): \(v)")
                }
            }
        }

        if let tests = ctx["failing_tests"] as? [String], !tests.isEmpty {
            lines.append("failing_tests: \(tests.joined(separator: ", "))")
        }

        if let peers = ctx["active_peers"] as? [[String: String]], !peers.isEmpty {
            lines.append("active_peers: \(peers.compactMap { $0["name"] }.joined(separator: ", "))")
        }

        if let md = ctx["claude_md"] as? String {
            // Truncate CLAUDE.md to first 1500 chars to avoid bloating the context
            let truncated = md.count > 1500 ? String(md.prefix(1500)) + "\n[...truncated]" : md
            lines.append("claude_md: |")
            truncated.components(separatedBy: "\n").forEach { lines.append("  \($0)") }
        }

        lines.append("</calyx_project_context>")
        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    private static func gitOutput(_ args: [String], in dir: String) -> String? {
        let proc = Process()
        let pipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        proc.arguments = args
        proc.currentDirectoryURL = URL(fileURLWithPath: dir)
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        guard (try? proc.run()) != nil else { return nil }
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    }

    private static func readFile(atPath path: String) -> String? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return try? String(contentsOfFile: path, encoding: .utf8)
    }
}
