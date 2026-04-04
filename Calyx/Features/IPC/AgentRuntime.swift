import Foundation
import GhosttyKit

enum AgentInputStyle: String, Sendable, Codable {
    case submitOnce
    case confirmPasteThenSubmit
}

enum AgentRuntimePreset: String, CaseIterable, Identifiable, Sendable {
    case claudeCode
    case codex
    case ollama
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .ollama: return "Ollama"
        case .custom: return "Custom"
        }
    }

    var defaultLaunchCommand: String {
        switch self {
        case .claudeCode:
            return "claude"
        case .codex:
            return "codex"
        case .ollama:
            return OllamaCommandService.currentLaunchCommand()
        case .custom:
            return ""
        }
    }

    var defaultRegistersWithIPC: Bool {
        switch self {
        case .claudeCode, .codex:
            return true
        case .ollama, .custom:
            return false
        }
    }

    var defaultInputStyle: AgentInputStyle {
        switch self {
        case .claudeCode, .codex:
            return .confirmPasteThenSubmit
        case .ollama, .custom:
            return .submitOnce
        }
    }
}

struct AgentRuntimeConfiguration: Sendable {
    let preset: AgentRuntimePreset
    let displayName: String
    let launchCommand: String
    let registersWithIPC: Bool
    let inputStyle: AgentInputStyle

    init(
        preset: AgentRuntimePreset,
        displayName: String,
        launchCommand: String,
        registersWithIPC: Bool,
        inputStyle: AgentInputStyle
    ) {
        self.preset = preset
        self.displayName = displayName
        self.launchCommand = launchCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        self.registersWithIPC = registersWithIPC
        self.inputStyle = inputStyle
    }

    init(preset: AgentRuntimePreset) {
        self.init(
            preset: preset,
            displayName: preset.displayName,
            launchCommand: preset.defaultLaunchCommand,
            registersWithIPC: preset.defaultRegistersWithIPC,
            inputStyle: preset.defaultInputStyle
        )
    }

    static let `default` = AgentRuntimeConfiguration(preset: .claudeCode)

    static func from(userInfo: [AnyHashable: Any]?) -> AgentRuntimeConfiguration {
        let preset = AgentRuntimePreset(rawValue: userInfo?["agentRuntimePreset"] as? String ?? "") ?? .claudeCode
        let base = AgentRuntimeConfiguration(preset: preset)
        let displayName = (userInfo?["agentDisplayName"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let launchCommand = (userInfo?["agentLaunchCommand"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let registersWithIPC = (userInfo?["agentRegistersWithIPC"] as? Bool) ?? base.registersWithIPC
        let inputStyle = AgentInputStyle(rawValue: userInfo?["agentInputStyle"] as? String ?? "") ?? base.inputStyle

        return AgentRuntimeConfiguration(
            preset: preset,
            displayName: (displayName?.isEmpty == false) ? displayName! : base.displayName,
            launchCommand: (launchCommand?.isEmpty == false) ? launchCommand! : base.launchCommand,
            registersWithIPC: registersWithIPC,
            inputStyle: inputStyle
        )
    }

    var notificationUserInfo: [String: Any] {
        [
            "agentRuntimePreset": preset.rawValue,
            "agentDisplayName": displayName,
            "agentLaunchCommand": launchCommand,
            "agentRegistersWithIPC": registersWithIPC,
            "agentInputStyle": inputStyle.rawValue,
        ]
    }

    static let knownAgentMarkers: [String] = [
        "claude",
        "codex",
        "ollama",
        "qwen",
        "deepseek",
        "llama",
        "mistral",
    ]

    static func isLikelyAgentTitle(_ title: String) -> Bool {
        let lower = title.lowercased()
        return knownAgentMarkers.contains { lower.contains($0) }
    }
}

enum AgentTextRouter {
    @MainActor
    static func submit(
        _ text: String,
        to controller: GhosttySurfaceController,
        inputStyle: AgentInputStyle,
        sendEnterKey: @escaping (GhosttySurfaceController) -> Void
    ) {
        controller.sendText(text)

        switch inputStyle {
        case .submitOnce:
            sendEnterKey(controller)
        case .confirmPasteThenSubmit:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                sendEnterKey(controller)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    sendEnterKey(controller)
                }
            }
        }
    }
}
