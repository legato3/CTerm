//
//  MCPClient.swift
//  CalyxCLI
//
//  HTTP client that communicates with CalyxMCPServer via JSON-RPC.
//

import Foundation

struct MCPClient {
    let port: Int
    let token: String

    /// Read connection info from ~/.config/calyx/ipc.json
    static func fromStateFile() throws -> MCPClient {
        let stateFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/calyx/ipc.json")

        guard FileManager.default.fileExists(atPath: stateFile.path) else {
            throw CLIError.notRunning
        }

        let data = try Data(contentsOf: stateFile)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let port = json["port"] as? Int,
              let token = json["token"] as? String else {
            throw CLIError.invalidStateFile
        }
        return MCPClient(port: port, token: token)
    }

    /// Send a tool call and return the text result.
    func callTool(name: String, arguments: [String: Any] = [:]) throws -> String {
        let requestBody: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/call",
            "params": [
                "name": name,
                "arguments": arguments,
            ],
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: requestBody)
        guard let bodyStr = String(data: bodyData, encoding: .utf8) else {
            throw CLIError.invalidResponse
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        proc.arguments = [
            "-s", "--connect-timeout", "5",
            "-X", "POST",
            "-H", "Authorization: Bearer \(token)",
            "-H", "Content-Type: application/json",
            "-d", bodyStr,
            "http://127.0.0.1:\(port)/mcp",
        ]

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        try proc.run()
        proc.waitUntilExit()

        guard proc.terminationStatus == 0 else {
            throw CLIError.connectionFailed("curl exit code \(proc.terminationStatus)")
        }

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let content = result["content"] as? [[String: Any]],
              let first = content.first,
              let text = first["text"] as? String else {
            throw CLIError.invalidResponse
        }

        // Check if the tool returned an error
        if let isError = result["isError"] as? Bool, isError {
            throw CLIError.toolError(text)
        }

        return text
    }
}

enum CLIError: Error, CustomStringConvertible {
    case notRunning
    case invalidStateFile
    case connectionFailed(String)
    case invalidResponse
    case toolError(String)

    var description: String {
        switch self {
        case .notRunning:
            return "Calyx is not running or IPC is not enabled. Start Calyx and enable IPC via Command Palette."
        case .invalidStateFile:
            return "Invalid IPC state file at ~/.config/calyx/ipc.json"
        case .connectionFailed(let msg):
            return "Connection failed: \(msg)"
        case .invalidResponse:
            return "Invalid response from server"
        case .toolError(let msg):
            return msg
        }
    }
}
