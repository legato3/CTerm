// SlashParser.swift
// CTerm
//
// Parses compose-bar input that begins with `/` into a SlashCommandInvocation.
// Supports plain `/name`, space-separated args, and double-quoted args.

import Foundation

@MainActor
enum SlashParser {

    /// Returns true if `text` starts with `/` at character 0 (strict — no
    /// leading whitespace and no mid-line matches).
    static func isSlashPrefix(_ text: String) -> Bool {
        guard let first = text.first else { return false }
        return first == "/"
    }

    /// Parses `raw` into a SlashCommandInvocation. Returns nil if `raw` does
    /// not start with `/`, has no name, or references an unknown command.
    static func parse(_ raw: String) -> SlashCommandInvocation? {
        guard isSlashPrefix(raw) else { return nil }
        let afterSlash = raw.dropFirst()
        guard !afterSlash.isEmpty else { return nil }

        // Separate the command name from the arg string.
        let nameEndIdx = afterSlash.firstIndex(where: { $0.isWhitespace }) ?? afterSlash.endIndex
        let name = String(afterSlash[..<nameEndIdx])
        guard !name.isEmpty else { return nil }

        guard let command = SlashCommandRegistry.lookup(name: name) else { return nil }

        let argsSlice = afterSlash[nameEndIdx...]
            .drop(while: { $0.isWhitespace })
        let args = tokenize(String(argsSlice))
        return SlashCommandInvocation(command: command, args: args)
    }

    /// Splits an arg string on whitespace, honoring double-quoted runs as
    /// single tokens.
    private static func tokenize(_ input: String) -> [String] {
        guard !input.isEmpty else { return [] }

        var tokens: [String] = []
        var current = ""
        var inQuotes = false

        for ch in input {
            if ch == "\"" {
                inQuotes.toggle()
                continue
            }
            if ch.isWhitespace && !inQuotes {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                continue
            }
            current.append(ch)
        }

        if !current.isEmpty {
            tokens.append(current)
        }

        return tokens
    }
}
