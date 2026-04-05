// ChangedFileExtractor.swift
// CTerm
//
// Translates `git diff --numstat HEAD` + `git status --porcelain` output
// into `[ChangedFile]`. The parsing functions are pure — they take raw
// strings — so they are unit-testable without shelling out to git.
//
// The `extract(workDir:)` entry point invokes GitService to run the
// actual git commands, merges the two sources, and returns a deduplicated
// list of ChangedFile records. If the directory is not a git repo or git
// fails for any reason, it returns an empty array rather than throwing.

import Foundation

@MainActor
enum ChangedFileExtractor {

    /// Runs `git diff --numstat HEAD` + `git status --porcelain` in `workDir`
    /// and merges the two into a list of `ChangedFile`. Returns an empty
    /// array if the directory is not a git repository.
    static func extract(workDir: String) async -> [ChangedFile] {
        guard await GitService.isGitRepository(workDir: workDir) else { return [] }

        async let numstatOutput = (try? await GitService.numstatSinceHead(workDir: workDir)) ?? ""
        async let porcelainOutput = (try? await GitService.porcelainStatus(workDir: workDir)) ?? ""

        let numstats = parseNumstat(await numstatOutput)
        let porcelain = parsePorcelain(await porcelainOutput)
        return merge(numstats: numstats, porcelain: porcelain, workDir: workDir)
    }

    // MARK: - Parsers (pure, testable)

    /// One parsed line of `git diff --numstat HEAD`.
    struct NumstatEntry: Equatable, Sendable {
        let additions: Int
        let deletions: Int
        let path: String
        let oldPath: String?  // set only for renames
    }

    /// One parsed line of `git status --porcelain`.
    struct PorcelainEntry: Equatable, Sendable {
        let status: ChangedFile.Status
        let path: String
        let oldPath: String?
    }

    static func parseNumstat(_ raw: String) -> [NumstatEntry] {
        var result: [NumstatEntry] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            // Format: "<additions>\t<deletions>\t<path>"
            // Renames emit: "<additions>\t<deletions>\toldpath => newpath"
            // or "<additions>\t<deletions>\tdir/{old => new}/file"
            let fields = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard fields.count == 3 else { continue }
            let addRaw = String(fields[0])
            let delRaw = String(fields[1])
            let pathField = String(fields[2])
            // Binary files show "-\t-\tpath"; skip binary counts to zero.
            let additions = Int(addRaw) ?? 0
            let deletions = Int(delRaw) ?? 0

            if let (oldPath, newPath) = expandRenamePath(pathField) {
                result.append(NumstatEntry(
                    additions: additions, deletions: deletions,
                    path: newPath, oldPath: oldPath
                ))
            } else {
                result.append(NumstatEntry(
                    additions: additions, deletions: deletions,
                    path: pathField, oldPath: nil
                ))
            }
        }
        return result
    }

    static func parsePorcelain(_ raw: String) -> [PorcelainEntry] {
        var result: [PorcelainEntry] = []
        for rawLine in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            // Porcelain lines are at least 4 chars: XY SP path
            guard rawLine.count >= 4 else { continue }
            let line = String(rawLine)
            let idxStart = line.startIndex
            let xChar = line[idxStart]
            let yCharIdx = line.index(after: idxStart)
            let yChar = line[yCharIdx]
            // Strip "XY " prefix (3 chars)
            let pathStart = line.index(idxStart, offsetBy: 3)
            let rest = String(line[pathStart...])

            if xChar == "?" && yChar == "?" {
                result.append(PorcelainEntry(status: .untracked, path: rest, oldPath: nil))
                continue
            }

            // Rename prefix appears on either X or Y side in porcelain v1.
            if xChar == "R" || yChar == "R" {
                if let arrow = rest.range(of: " -> ") {
                    let oldPath = String(rest[..<arrow.lowerBound])
                    let newPath = String(rest[arrow.upperBound...])
                    result.append(PorcelainEntry(status: .renamed, path: newPath, oldPath: oldPath))
                    continue
                }
            }

            let status: ChangedFile.Status? = {
                // Prefer the index status (X); fall back to worktree (Y).
                if let s = mapStatusChar(xChar) { return s }
                return mapStatusChar(yChar)
            }()
            guard let status else { continue }
            result.append(PorcelainEntry(status: status, path: rest, oldPath: nil))
        }
        return result
    }

    /// Merge numstat (authoritative add/del counts) with porcelain status
    /// (authoritative A/M/D/R/untracked classification), returning one
    /// ChangedFile per path. Untracked files in porcelain that aren't in
    /// numstat get a best-effort line count.
    static func merge(
        numstats: [NumstatEntry],
        porcelain: [PorcelainEntry],
        workDir: String
    ) -> [ChangedFile] {
        // Index porcelain by path for status lookup.
        var statusByPath: [String: PorcelainEntry] = [:]
        for entry in porcelain { statusByPath[entry.path] = entry }

        var seen: Set<String> = []
        var out: [ChangedFile] = []

        for stat in numstats {
            let status: ChangedFile.Status = statusByPath[stat.path]?.status ?? .modified
            let oldPath = stat.oldPath ?? statusByPath[stat.path]?.oldPath
            out.append(ChangedFile(
                path: stat.path,
                status: status,
                additions: stat.additions,
                deletions: stat.deletions,
                oldPath: oldPath
            ))
            seen.insert(stat.path)
        }

        // Anything in porcelain not yet covered — mostly untracked files,
        // since `git diff --numstat HEAD` won't report them.
        for entry in porcelain where !seen.contains(entry.path) {
            var additions = 0
            if entry.status == .untracked {
                additions = countLinesInFile(path: entry.path, workDir: workDir)
            }
            out.append(ChangedFile(
                path: entry.path,
                status: entry.status,
                additions: additions,
                deletions: 0,
                oldPath: entry.oldPath
            ))
        }

        return out
    }

    // MARK: - Helpers

    private static func mapStatusChar(_ c: Character) -> ChangedFile.Status? {
        switch c {
        case "A": return .added
        case "M": return .modified
        case "D": return .deleted
        case "R": return .renamed
        case "T": return .modified
        case "C": return .added
        case " ": return nil
        case "?": return .untracked
        default:  return nil
        }
    }

    /// Expands the numstat rename notation into (oldPath, newPath).
    ///
    /// Forms:
    ///   "old => new"
    ///   "src/{old => new}/file.swift"
    /// Returns nil if the field is a plain path.
    static func expandRenamePath(_ field: String) -> (String, String)? {
        if let brace = field.range(of: "{") {
            guard let close = field.range(of: "}", range: brace.upperBound..<field.endIndex) else {
                return nil
            }
            let prefix = String(field[..<brace.lowerBound])
            let inner = String(field[brace.upperBound..<close.lowerBound])
            let suffix = String(field[close.upperBound...])
            guard let arrow = inner.range(of: " => ") else { return nil }
            let innerOld = String(inner[..<arrow.lowerBound])
            let innerNew = String(inner[arrow.upperBound...])
            let oldPath = (prefix + innerOld + suffix).replacingOccurrences(of: "//", with: "/")
            let newPath = (prefix + innerNew + suffix).replacingOccurrences(of: "//", with: "/")
            return (oldPath, newPath)
        }
        if let arrow = field.range(of: " => ") {
            let oldPath = String(field[..<arrow.lowerBound])
            let newPath = String(field[arrow.upperBound...])
            return (oldPath, newPath)
        }
        return nil
    }

    private static func countLinesInFile(path: String, workDir: String) -> Int {
        let full = (workDir as NSString).appendingPathComponent(path)
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: full)),
              let text = String(data: data, encoding: .utf8) else {
            return 0
        }
        // Match `wc -l` semantics: count newline characters.
        return text.reduce(0) { $1 == "\n" ? $0 + 1 : $0 }
    }
}
