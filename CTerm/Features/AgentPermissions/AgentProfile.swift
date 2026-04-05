// AgentProfile.swift
// CTerm
//
// Named permission bundle layered on top of the grant/trust-mode system.
// Each session captures the active profile id at spawn time; ApprovalGate
// consults the profile *after* HardStopGuard but *before* AgentGrantStore
// so that profile blocks and caps take precedence over cached grants.
//
// Built-in profiles ship with the app and cannot be deleted. Custom
// profiles are persisted to ~/.cterm/profiles.json.

import Foundation

struct AgentProfile: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var description: String
    var icon: String                                 // SF Symbol name
    var trustMode: AgentTrustMode
    var autoApproveCategories: Set<AgentActionCategory>
    var blockedCategories: Set<AgentActionCategory>
    var maxRiskTier: RiskTier
    var isBuiltIn: Bool
    /// Optional hard-override backend for the ModelRouter. When non-nil,
    /// every step routed through ModelRouter.pick(...) for a session using
    /// this profile returns this backend regardless of the active preset.
    /// Nil (default) means "follow the routing preset".
    var preferredBackend: AgentBackend?

    init(
        id: UUID = UUID(),
        name: String,
        description: String,
        icon: String,
        trustMode: AgentTrustMode,
        autoApproveCategories: Set<AgentActionCategory>,
        blockedCategories: Set<AgentActionCategory>,
        maxRiskTier: RiskTier,
        isBuiltIn: Bool,
        preferredBackend: AgentBackend? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.icon = icon
        self.trustMode = trustMode
        self.autoApproveCategories = autoApproveCategories
        self.blockedCategories = blockedCategories
        self.maxRiskTier = maxRiskTier
        self.isBuiltIn = isBuiltIn
        self.preferredBackend = preferredBackend
    }
}

// MARK: - Built-in profiles

extension AgentProfile {

    /// Stable UUIDs so active-profile selection survives app upgrades.
    enum BuiltInID {
        static let readOnly    = UUID(uuidString: "11111111-1111-1111-1111-111111110001")
            ?? UUID()
        static let sandboxRepo = UUID(uuidString: "11111111-1111-1111-1111-111111110002")
            ?? UUID()
        static let standard    = UUID(uuidString: "11111111-1111-1111-1111-111111110003")
            ?? UUID()
        static let fullAuto    = UUID(uuidString: "11111111-1111-1111-1111-111111110004")
            ?? UUID()
    }

    static let readOnly = AgentProfile(
        id: BuiltInID.readOnly,
        name: "Read-only",
        description: "Only reads and lookups. Anything that writes, deletes, or touches the network is blocked.",
        icon: "eye",
        trustMode: .askMe,
        autoApproveCategories: [.readFiles],
        blockedCategories: [
            .writeFiles,
            .deleteFiles,
            .runCommands,
            .networkAccess,
            .gitOperations,
            .browserAutomation
        ],
        maxRiskTier: .low,
        isBuiltIn: true
    )

    static let sandboxRepo = AgentProfile(
        id: BuiltInID.sandboxRepo,
        name: "Sandbox (repo)",
        description: "Reads and safe repo commands auto-approve. Network and deletes are blocked.",
        icon: "folder.badge.gearshape",
        trustMode: .askMe,
        autoApproveCategories: [.readFiles, .gitOperations],
        blockedCategories: [.networkAccess, .deleteFiles, .browserAutomation],
        maxRiskTier: .medium,
        isBuiltIn: true
    )

    static let standard = AgentProfile(
        id: BuiltInID.standard,
        name: "Standard",
        description: "The default: reads auto-approve, everything else asks.",
        icon: "slider.horizontal.3",
        trustMode: .askMe,
        autoApproveCategories: [.readFiles],
        blockedCategories: [],
        maxRiskTier: .high,
        isBuiltIn: true
    )

    static let fullAuto = AgentProfile(
        id: BuiltInID.fullAuto,
        name: "Full Auto",
        description: "Trust the session. Only destructive hard-stops interrupt.",
        icon: "bolt.fill",
        trustMode: .trustSession,
        autoApproveCategories: Set(AgentActionCategory.allCases.filter { $0 != .interactivePrompt }),
        blockedCategories: [],
        maxRiskTier: .critical,
        isBuiltIn: true
    )

    static let builtIns: [AgentProfile] = [.readOnly, .sandboxRepo, .standard, .fullAuto]
}
