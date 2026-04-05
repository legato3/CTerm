// AgentProfileStore.swift
// CTerm
//
// Holds the set of available AgentProfiles (built-ins + user-defined custom
// profiles) and the currently active profile id. Custom profiles persist to
// ~/.cterm/profiles.json. The active id persists to UserDefaults.
//
// Built-ins are seeded on every launch and are not written to disk; deleting
// a built-in is refused.

import Foundation
import Observation
import OSLog

private let logger = Logger(subsystem: "com.legato3.cterm", category: "AgentProfileStore")

@Observable
@MainActor
final class AgentProfileStore {

    static let shared = AgentProfileStore()

    private static let activeIDDefaultsKey = "CTerm.AgentProfile.ActiveID"

    private(set) var profiles: [AgentProfile]

    var activeProfileID: UUID {
        didSet {
            guard oldValue != activeProfileID else { return }
            UserDefaults.standard.set(activeProfileID.uuidString, forKey: Self.activeIDDefaultsKey)
        }
    }

    // Exposed for test hooks to override default storage.
    private let storageURL: URL

    // MARK: - Init

    private init() {
        self.storageURL = Self.defaultStorageURL()
        self.profiles = AgentProfile.builtIns
        self.activeProfileID = AgentProfile.standard.id
        loadCustomProfiles()
        restoreActiveID()
    }

    #if DEBUG
    /// Test-only initializer so unit tests can use an isolated on-disk file.
    init(storageURL: URL, seedBuiltIns: Bool = true) {
        self.storageURL = storageURL
        self.profiles = seedBuiltIns ? AgentProfile.builtIns : []
        self.activeProfileID = AgentProfile.standard.id
        loadCustomProfiles()
    }
    #endif

    // MARK: - Computed

    var activeProfile: AgentProfile {
        profiles.first(where: { $0.id == activeProfileID }) ?? AgentProfile.standard
    }

    // MARK: - Lookup

    func profile(id: UUID) -> AgentProfile? {
        profiles.first(where: { $0.id == id })
    }

    // MARK: - Mutation

    enum ProfileError: Error, Equatable {
        case cannotDeleteBuiltIn
        case notFound
        case cannotModifyBuiltIn
    }

    @discardableResult
    func add(_ profile: AgentProfile) -> Bool {
        guard !profile.isBuiltIn else { return false }
        guard !profiles.contains(where: { $0.id == profile.id }) else { return false }
        profiles.append(profile)
        persistCustomProfiles()
        return true
    }

    func update(_ profile: AgentProfile) throws {
        guard let idx = profiles.firstIndex(where: { $0.id == profile.id }) else {
            throw ProfileError.notFound
        }
        if profiles[idx].isBuiltIn {
            throw ProfileError.cannotModifyBuiltIn
        }
        var updated = profile
        updated.isBuiltIn = false   // defensive
        profiles[idx] = updated
        persistCustomProfiles()
    }

    func delete(id: UUID) throws {
        guard let idx = profiles.firstIndex(where: { $0.id == id }) else {
            throw ProfileError.notFound
        }
        if profiles[idx].isBuiltIn {
            throw ProfileError.cannotDeleteBuiltIn
        }
        profiles.remove(at: idx)
        if activeProfileID == id {
            activeProfileID = AgentProfile.standard.id
        }
        persistCustomProfiles()
    }

    // MARK: - Persistence

    private static func defaultStorageURL() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".cterm/profiles.json")
    }

    private func loadCustomProfiles() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            let custom = try decoder.decode([AgentProfile].self, from: data)
            for var p in custom where !p.isBuiltIn {
                if !profiles.contains(where: { $0.id == p.id }) {
                    p.isBuiltIn = false
                    profiles.append(p)
                }
            }
        } catch {
            logger.warning("Failed to load custom profiles: \(error.localizedDescription)")
        }
    }

    private func restoreActiveID() {
        if let raw = UserDefaults.standard.string(forKey: Self.activeIDDefaultsKey),
           let uuid = UUID(uuidString: raw),
           profiles.contains(where: { $0.id == uuid }) {
            self.activeProfileID = uuid
        }
    }

    private func persistCustomProfiles() {
        let custom = profiles.filter { !$0.isBuiltIn }
        let dir = storageURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(custom)
            // Atomic write via temp + rename.
            let tmp = storageURL.appendingPathExtension("tmp")
            try data.write(to: tmp, options: .atomic)
            if FileManager.default.fileExists(atPath: storageURL.path) {
                _ = try? FileManager.default.removeItem(at: storageURL)
            }
            try FileManager.default.moveItem(at: tmp, to: storageURL)
        } catch {
            logger.error("Failed to persist custom profiles: \(error.localizedDescription)")
        }
    }
}
