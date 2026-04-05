// SessionSnapshot.swift
// CTerm
//
// Codable DTOs for session persistence. Off-main-thread safe.

import Foundation

struct SessionSnapshot: Codable, Equatable {
    static let currentSchemaVersion = 5

    let schemaVersion: Int
    let windows: [WindowSnapshot]
    /// Named workspace tag. `nil` for the auto-save slot; set when saving as a named workspace.
    var workspaceName: String?
    /// Active agent sessions at snapshot time. Restored into AgentSessionRegistry on launch.
    var agentSessions: [AgentSessionSnapshot]?

    init(schemaVersion: Int = Self.currentSchemaVersion,
         windows: [WindowSnapshot] = [],
         workspaceName: String? = nil,
         agentSessions: [AgentSessionSnapshot]? = nil) {
        self.schemaVersion = schemaVersion
        self.windows = windows
        self.workspaceName = workspaceName
        self.agentSessions = agentSessions
    }
}

extension SessionSnapshot {
    /// Stepwise migration pipeline. Add a new step here when bumping currentSchemaVersion.
    static func migrate(_ snapshot: SessionSnapshot) -> SessionSnapshot {
        var current = snapshot
        if current.schemaVersion < 2 { current = migrateV1ToV2(current) }
        if current.schemaVersion < 3 { current = migrateV2ToV3(current) }
        if current.schemaVersion < 4 { current = migrateV3ToV4(current) }
        if current.schemaVersion < 5 { current = migrateV4ToV5(current) }
        return SessionSnapshot(
            schemaVersion: currentSchemaVersion,
            windows: current.windows,
            workspaceName: current.workspaceName,
            agentSessions: current.agentSessions
        )
    }

    // v1 → v2: no structural changes; optional field defaults handled by Decodable.
    private static func migrateV1ToV2(_ s: SessionSnapshot) -> SessionSnapshot {
        SessionSnapshot(schemaVersion: 2, windows: s.windows)
    }

    // v2 → v3: no structural changes; optional field defaults handled by Decodable.
    private static func migrateV2ToV3(_ s: SessionSnapshot) -> SessionSnapshot {
        SessionSnapshot(schemaVersion: 3, windows: s.windows)
    }

    // v3 → v4: no structural changes; optional field defaults handled by Decodable.
    private static func migrateV3ToV4(_ s: SessionSnapshot) -> SessionSnapshot {
        SessionSnapshot(schemaVersion: 4, windows: s.windows)
    }

    // v4 → v5: adds optional `agentSessions` at the top level (defaulted to nil by Decodable).
    private static func migrateV4ToV5(_ s: SessionSnapshot) -> SessionSnapshot {
        SessionSnapshot(schemaVersion: 5, windows: s.windows, workspaceName: s.workspaceName, agentSessions: nil)
    }
}

struct WindowSnapshot: Codable, Equatable {
    let id: UUID
    let frame: CGRect
    let groups: [TabGroupSnapshot]
    let activeGroupID: UUID?
    let showSidebar: Bool
    let sidebarWidth: CGFloat

    private enum CodingKeys: String, CodingKey {
        case id, frame, groups, activeGroupID, showSidebar, sidebarWidth
    }

    init(id: UUID = UUID(), frame: CGRect = .zero, groups: [TabGroupSnapshot] = [], activeGroupID: UUID? = nil, showSidebar: Bool = true, sidebarWidth: CGFloat = SidebarLayout.defaultWidth) {
        self.id = id
        self.frame = frame
        self.groups = groups
        self.activeGroupID = activeGroupID
        self.showSidebar = showSidebar
        self.sidebarWidth = sidebarWidth
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        frame = try container.decode(CGRect.self, forKey: .frame)
        groups = try container.decode([TabGroupSnapshot].self, forKey: .groups)
        activeGroupID = try container.decodeIfPresent(UUID.self, forKey: .activeGroupID)
        showSidebar = try container.decodeIfPresent(Bool.self, forKey: .showSidebar) ?? true
        let rawWidth = try container.decodeIfPresent(CGFloat.self, forKey: .sidebarWidth) ?? SidebarLayout.defaultWidth
        sidebarWidth = SidebarLayout.clampWidth(rawWidth)
    }

    func clampedToScreen(screenFrame: CGRect) -> WindowSnapshot {
        // If frame doesn't intersect screen at all, center it
        if !screenFrame.intersects(frame) {
            let w = max(frame.width, 400)
            let h = max(frame.height, 300)
            let centered = CGRect(
                x: screenFrame.midX - w / 2,
                y: screenFrame.midY - h / 2,
                width: w, height: h
            )
            return WindowSnapshot(id: id, frame: centered, groups: groups, activeGroupID: activeGroupID, showSidebar: showSidebar, sidebarWidth: sidebarWidth)
        }

        var f = frame
        // Enforce minimum size first so clamping uses correct dimensions
        f.size.width = max(f.size.width, 400)
        f.size.height = max(f.size.height, 300)
        if f.origin.x < screenFrame.origin.x { f.origin.x = screenFrame.origin.x }
        if f.origin.y < screenFrame.origin.y { f.origin.y = screenFrame.origin.y }
        if f.maxX > screenFrame.maxX { f.origin.x = screenFrame.maxX - f.width }
        if f.maxY > screenFrame.maxY { f.origin.y = screenFrame.maxY - f.height }
        return WindowSnapshot(id: id, frame: f, groups: groups, activeGroupID: activeGroupID, showSidebar: showSidebar, sidebarWidth: sidebarWidth)
    }
}

struct TabGroupSnapshot: Codable, Equatable {
    let id: UUID
    let name: String
    let color: String?
    let tabs: [TabSnapshot]
    let activeTabID: UUID?
    let isCollapsed: Bool

    private enum CodingKeys: String, CodingKey {
        case id, name, color, tabs, activeTabID, isCollapsed
    }

    init(id: UUID = UUID(), name: String = "Default", color: String? = nil, tabs: [TabSnapshot] = [], activeTabID: UUID? = nil, isCollapsed: Bool = false) {
        self.id = id
        self.name = name
        self.color = color
        self.tabs = tabs
        self.activeTabID = activeTabID
        self.isCollapsed = isCollapsed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        color = try container.decodeIfPresent(String.self, forKey: .color)
        tabs = try container.decode([TabSnapshot].self, forKey: .tabs)
        activeTabID = try container.decodeIfPresent(UUID.self, forKey: .activeTabID)
        isCollapsed = try container.decodeIfPresent(Bool.self, forKey: .isCollapsed) ?? false
    }
}

struct TabSnapshot: Codable, Equatable {
    let id: UUID
    let title: String
    let titleOverride: String?
    let pwd: String?
    let splitTree: SplitTree
    let browserURL: URL?
    /// Block IDs pinned as attachments at save time. Nil for legacy snapshots.
    let attachedBlockIDs: [UUID]?
    /// Bounded set of command blocks persisted for attachment continuity across restart.
    /// Nil for legacy snapshots (decoded as nil via decodeIfPresent).
    let persistedBlocks: [PersistedCommandBlock]?

    private enum CodingKeys: String, CodingKey {
        case id, title, titleOverride, pwd, splitTree, browserURL
        case attachedBlockIDs, persistedBlocks
    }

    init(id: UUID = UUID(),
         title: String = "Terminal",
         titleOverride: String? = nil,
         pwd: String? = nil,
         splitTree: SplitTree = SplitTree(),
         browserURL: URL? = nil,
         attachedBlockIDs: [UUID]? = nil,
         persistedBlocks: [PersistedCommandBlock]? = nil) {
        self.id = id
        self.title = title
        self.titleOverride = titleOverride
        self.pwd = pwd
        self.splitTree = splitTree
        self.browserURL = browserURL
        self.attachedBlockIDs = attachedBlockIDs
        self.persistedBlocks = persistedBlocks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        titleOverride = try container.decodeIfPresent(String.self, forKey: .titleOverride)
        pwd = try container.decodeIfPresent(String.self, forKey: .pwd)
        splitTree = try container.decode(SplitTree.self, forKey: .splitTree)
        browserURL = try container.decodeIfPresent(URL.self, forKey: .browserURL)
        attachedBlockIDs = try container.decodeIfPresent([UUID].self, forKey: .attachedBlockIDs)
        persistedBlocks = try container.decodeIfPresent([PersistedCommandBlock].self, forKey: .persistedBlocks)
    }
}

/// Codable, off-main-thread-safe projection of `TerminalCommandBlock` for persistence.
/// Mirrors the runtime fields but omits `surfaceID` binding concerns — surface IDs are
/// regenerated on restore, so this field is stored as optional and tolerated nil on decode.
struct PersistedCommandBlock: Codable, Equatable {
    let id: UUID
    let source: String           // raw value of TerminalCommandSource
    let surfaceID: UUID?
    let command: String?
    let startedAt: Date
    let finishedAt: Date?
    let status: String           // raw value of TerminalCommandStatus
    let outputSnippet: String?
    let errorSnippet: String?
    let exitCode: Int?
    let durationNanoseconds: UInt64?
    let cwd: String?

    /// Maximum number of lines retained in output/error snippets on persist. Matches
    /// the F1 viewport capture cap to keep snapshot payloads bounded.
    static let snippetLineCap = 32
}

// MARK: - Conversion to/from Runtime Models

extension AppSession {
    @MainActor
    func snapshot() -> SessionSnapshot {
        let active = AgentSessionRegistry.shared.all.map { $0.persistenceSnapshot() }
        return SessionSnapshot(
            windows: windows.map { $0.snapshot() },
            agentSessions: active.isEmpty ? nil : active
        )
    }
}

extension WindowSession {
    func snapshot() -> WindowSnapshot {
        WindowSnapshot(
            id: id,
            frame: .zero, // Frame is set by the caller from NSWindow
            groups: groups.map { $0.snapshot() },
            activeGroupID: activeGroupID,
            showSidebar: showSidebar,
            sidebarWidth: sidebarWidth
        )
    }
}

extension TabGroup {
    func snapshot() -> TabGroupSnapshot {
        TabGroupSnapshot(
            id: id,
            name: name,
            color: color.rawValue,
            tabs: tabs.compactMap { $0.snapshot() },
            activeTabID: activeTabID,
            isCollapsed: isCollapsed
        )
    }
}

extension Tab {
    func snapshot() -> TabSnapshot? {
        switch content {
        case .diff:
            return nil  // Diff tabs are not persisted
        case .terminal:
            return TabSnapshotBuilder.build(from: self, browserURL: nil)
        case .browser(let url):
            return TabSnapshotBuilder.build(from: self, browserURL: url)
        }
    }

    convenience init(snapshot: TabSnapshot) {
        let content: TabContent = if let url = snapshot.browserURL {
            .browser(url: url)
        } else {
            .terminal
        }
        self.init(
            id: snapshot.id,
            title: snapshot.title,
            titleOverride: snapshot.titleOverride,
            pwd: snapshot.pwd,
            splitTree: snapshot.splitTree,
            content: content
        )
        TabSnapshotBuilder.apply(snapshot: snapshot, to: self)
    }
}

// MARK: - TabSnapshotBuilder

/// Pure helpers for converting `Tab` ↔ `TabSnapshot` with attachment/block persistence.
/// Extracted so round-trip logic is testable in isolation.
@MainActor
enum TabSnapshotBuilder {
    /// Maximum number of recent blocks persisted per tab.
    static let recentBlockCap = 20

    static func build(from tab: Tab, browserURL: URL?) -> TabSnapshot {
        let attachedIDs = Array(tab.attachedBlockIDs)
        let persisted = collectPersistedBlocks(from: tab)
        return TabSnapshot(
            id: tab.id,
            title: tab.title,
            titleOverride: tab.titleOverride,
            pwd: tab.pwd,
            splitTree: tab.splitTree,
            browserURL: browserURL,
            attachedBlockIDs: attachedIDs.isEmpty ? nil : attachedIDs,
            persistedBlocks: persisted.isEmpty ? nil : persisted
        )
    }

    static func apply(snapshot: TabSnapshot, to tab: Tab) {
        if let persisted = snapshot.persistedBlocks, !persisted.isEmpty {
            let restored = persisted.map { $0.toRuntimeBlock() }
            tab.blockStore.replaceAll(with: restored)
        }
        if let attached = snapshot.attachedBlockIDs, !attached.isEmpty {
            let availableIDs = Set(tab.blockStore.all.map { $0.id })
            for id in attached where availableIDs.contains(id) {
                tab.attachBlock(id)
            }
        }
    }

    /// Collects the union of the 20 most-recent blocks and any blocks referenced by
    /// `attachedBlockIDs`, deduplicated by id and preserving newest-first order with
    /// referenced-but-older attached blocks appended after.
    private static func collectPersistedBlocks(from tab: Tab) -> [PersistedCommandBlock] {
        let all = tab.commandBlocks
        guard !all.isEmpty else { return [] }
        let recent = Array(all.prefix(recentBlockCap))
        var seen = Set(recent.map { $0.id })
        var result = recent
        if !tab.attachedBlockIDs.isEmpty {
            for block in all where tab.attachedBlockIDs.contains(block.id) && !seen.contains(block.id) {
                result.append(block)
                seen.insert(block.id)
            }
        }
        return result.map { PersistedCommandBlock(from: $0) }
    }
}

// MARK: - PersistedCommandBlock ↔ TerminalCommandBlock

extension PersistedCommandBlock {
    init(from block: TerminalCommandBlock) {
        self.id = block.id
        self.source = block.source.rawValue
        self.surfaceID = block.surfaceID
        self.command = block.command
        self.startedAt = block.startedAt
        self.finishedAt = block.finishedAt
        self.status = block.status.rawValue
        self.outputSnippet = PersistedCommandBlock.truncateSnippet(block.outputSnippet)
        self.errorSnippet = PersistedCommandBlock.truncateSnippet(block.errorSnippet)
        self.exitCode = block.exitCode
        self.durationNanoseconds = block.durationNanoseconds
        self.cwd = block.cwd
    }

    func toRuntimeBlock() -> TerminalCommandBlock {
        TerminalCommandBlock(
            id: id,
            source: TerminalCommandSource(rawValue: source) ?? .shell,
            surfaceID: nil, // surface UUIDs are regenerated at restore; don't bind to stale ones
            command: command,
            startedAt: startedAt,
            finishedAt: finishedAt,
            status: TerminalCommandStatus(rawValue: status) ?? .succeeded,
            outputSnippet: outputSnippet,
            errorSnippet: errorSnippet,
            exitCode: exitCode,
            durationNanoseconds: durationNanoseconds,
            cwd: cwd
        )
    }

    /// Truncates a snippet to the last `snippetLineCap` non-empty lines to bound payload size.
    static func truncateSnippet(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return text }
        let lines = text.components(separatedBy: CharacterSet.newlines)
        guard lines.count > snippetLineCap else { return text }
        return lines.suffix(snippetLineCap).joined(separator: "\n")
    }
}

extension TabGroup {
    convenience init(snapshot: TabGroupSnapshot) {
        let tabs = snapshot.tabs.map { Tab(snapshot: $0) }
        let color = TabGroupColor(rawValue: snapshot.color ?? "blue") ?? .blue
        self.init(
            id: snapshot.id,
            name: snapshot.name,
            color: color,
            isCollapsed: snapshot.isCollapsed,
            tabs: tabs,
            activeTabID: snapshot.activeTabID
        )
    }
}

extension WindowSession {
    convenience init(snapshot: WindowSnapshot) {
        let groups = snapshot.groups.map { TabGroup(snapshot: $0) }
        self.init(
            id: snapshot.id,
            groups: groups,
            activeGroupID: snapshot.activeGroupID,
            showSidebar: snapshot.showSidebar,
            sidebarWidth: snapshot.sidebarWidth
        )
    }
}
