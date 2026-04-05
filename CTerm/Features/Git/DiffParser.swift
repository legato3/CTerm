// DiffParser.swift
// CTerm
//
// Parses unified diff output into structured DiffLine arrays.

import Foundation

enum DiffParser {
    private static let maxBytes = 1_000_000
    private static let maxLines = 50_000

    static func parse(_ raw: String, path: String) -> FileDiff {
        guard !raw.isEmpty else {
            return FileDiff(path: path, lines: [], isBinary: false, isTruncated: false)
        }

        var input = raw
        var isTruncated = false

        if input.utf8.count > maxBytes {
            // Truncate on a Unicode scalar boundary to avoid splitting a multi-byte character.
            let utf8 = input.utf8
            var idx = utf8.index(utf8.startIndex, offsetBy: maxBytes)
            // Walk back until we're on a scalar boundary (continuation bytes start with 10xxxxxx).
            while idx > utf8.startIndex && (utf8[idx] & 0xC0) == 0x80 {
                idx = utf8.index(before: idx)
            }
            input = String(input[..<idx])
            isTruncated = true
        }

        let rawLines = input.components(separatedBy: "\n")
        var lines: [DiffLine] = []
        var hunks: [DiffHunk] = []
        var isBinary = false

        var inHunk = false
        var oldLine = 0
        var newLine = 0

        // In-progress hunk state for building the structured `hunks` array.
        var currentHeader: String? = nil
        var currentOldStart = 0
        var currentOldCount = 0
        var currentNewStart = 0
        var currentNewCount = 0
        var currentBody: [String] = []

        func flushHunk() {
            guard let header = currentHeader else { return }
            hunks.append(DiffHunk(
                header: header,
                oldStart: currentOldStart,
                oldCount: currentOldCount,
                newStart: currentNewStart,
                newCount: currentNewCount,
                bodyLines: currentBody
            ))
            currentHeader = nil
            currentBody = []
        }

        for rawLine in rawLines {
            if lines.count >= maxLines {
                isTruncated = true
                break
            }

            if rawLine.hasPrefix("diff --git ") {
                flushHunk()
                inHunk = false
                lines.append(DiffLine(type: .meta, text: rawLine, oldLineNumber: nil, newLineNumber: nil))
                continue
            }

            if !inHunk {
                if rawLine.hasPrefix("Binary files ") && rawLine.hasSuffix(" differ") {
                    isBinary = true
                    lines.append(DiffLine(type: .meta, text: rawLine, oldLineNumber: nil, newLineNumber: nil))
                    continue
                }
                if rawLine.hasPrefix("GIT binary patch") {
                    isBinary = true
                    lines.append(DiffLine(type: .meta, text: rawLine, oldLineNumber: nil, newLineNumber: nil))
                    continue
                }
                if rawLine.hasPrefix("@@") {
                    let parsed = parseHunkHeader(rawLine)
                    oldLine = parsed.oldStart
                    newLine = parsed.newStart
                    inHunk = true
                    flushHunk()
                    currentHeader = rawLine
                    currentOldStart = parsed.oldStart
                    currentOldCount = parsed.oldCount
                    currentNewStart = parsed.newStart
                    currentNewCount = parsed.newCount
                    currentBody = []
                    lines.append(DiffLine(type: .hunkHeader, text: rawLine, oldLineNumber: nil, newLineNumber: nil))
                    continue
                }
                if rawLine.hasPrefix("index ") || rawLine.hasPrefix("--- ") || rawLine.hasPrefix("+++ ") ||
                   rawLine.hasPrefix("new file mode") || rawLine.hasPrefix("deleted file mode") ||
                   rawLine.hasPrefix("rename from ") || rawLine.hasPrefix("rename to ") ||
                   rawLine.hasPrefix("similarity index") || rawLine.hasPrefix("old mode") ||
                   rawLine.hasPrefix("new mode") {
                    lines.append(DiffLine(type: .meta, text: rawLine, oldLineNumber: nil, newLineNumber: nil))
                    continue
                }
                lines.append(DiffLine(type: .meta, text: rawLine, oldLineNumber: nil, newLineNumber: nil))
                continue
            }

            // Inside hunk
            if rawLine.hasPrefix("@@") {
                let parsed = parseHunkHeader(rawLine)
                oldLine = parsed.oldStart
                newLine = parsed.newStart
                flushHunk()
                currentHeader = rawLine
                currentOldStart = parsed.oldStart
                currentOldCount = parsed.oldCount
                currentNewStart = parsed.newStart
                currentNewCount = parsed.newCount
                currentBody = []
                lines.append(DiffLine(type: .hunkHeader, text: rawLine, oldLineNumber: nil, newLineNumber: nil))
                continue
            }

            if rawLine.hasPrefix("+") {
                lines.append(DiffLine(type: .addition, text: rawLine, oldLineNumber: nil, newLineNumber: newLine))
                newLine += 1
                currentBody.append(rawLine)
                continue
            }

            if rawLine.hasPrefix("-") {
                lines.append(DiffLine(type: .deletion, text: rawLine, oldLineNumber: oldLine, newLineNumber: nil))
                oldLine += 1
                currentBody.append(rawLine)
                continue
            }

            if rawLine.hasPrefix(" ") || (rawLine.isEmpty && inHunk) {
                lines.append(DiffLine(type: .context, text: rawLine, oldLineNumber: oldLine, newLineNumber: newLine))
                oldLine += 1
                newLine += 1
                currentBody.append(rawLine.isEmpty ? " " : rawLine)
                continue
            }

            if rawLine.hasPrefix("\\") {
                lines.append(DiffLine(type: .meta, text: rawLine, oldLineNumber: nil, newLineNumber: nil))
                currentBody.append(rawLine)
                continue
            }

            lines.append(DiffLine(type: .meta, text: rawLine, oldLineNumber: nil, newLineNumber: nil))
        }

        flushHunk()
        return FileDiff(path: path, lines: lines, isBinary: isBinary, isTruncated: isTruncated, hunks: hunks)
    }

    private static func parseHunkHeader(_ line: String) -> (oldStart: Int, oldCount: Int, newStart: Int, newCount: Int) {
        let scanner = Scanner(string: line)
        _ = scanner.scanString("@@")
        _ = scanner.scanString("-")

        let oldStart = scanner.scanInt() ?? 1
        var oldCount = 1
        if scanner.scanString(",") != nil {
            oldCount = scanner.scanInt() ?? 1
        }

        _ = scanner.scanString("+")
        let newStart = scanner.scanInt() ?? 1
        var newCount = 1
        if scanner.scanString(",") != nil {
            newCount = scanner.scanInt() ?? 1
        }

        return (oldStart, oldCount, newStart, newCount)
    }
}
