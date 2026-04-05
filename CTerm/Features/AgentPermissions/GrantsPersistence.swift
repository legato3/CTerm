// GrantsPersistence.swift
// CTerm
//
// Actor-backed disk IO for per-repo approval grants. One JSON file per repo
// at ~/.cterm/grants/<repoKey>.json. Atomic writes; corruption is quarantined
// to a `.broken` sidecar file.

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.legato3.cterm", category: "GrantsPersistence")

actor GrantsPersistence {
    static let shared = GrantsPersistence()

    private let grantsDir: URL

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.grantsDir = home.appendingPathComponent(".cterm/grants", isDirectory: true)
        try? FileManager.default.createDirectory(at: grantsDir, withIntermediateDirectories: true)
    }

    // MARK: - Load

    func load(repoKey: String) -> RepoGrantsFile? {
        let url = fileURL(for: repoKey)
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder.iso8601.decode(RepoGrantsFile.self, from: data)
        } catch {
            logger.warning("Grants file \(repoKey) corrupt, quarantining: \(error.localizedDescription)")
            quarantine(url)
            return nil
        }
    }

    // MARK: - Save

    func save(_ file: RepoGrantsFile) {
        let url = fileURL(for: file.repoKey)
        do {
            let data = try JSONEncoder.iso8601Pretty.encode(file)
            let tmp = url.appendingPathExtension("tmp")
            try data.write(to: tmp, options: .atomic)
            // Move temp into place
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try? FileManager.default.removeItem(at: url)
            }
            try FileManager.default.moveItem(at: tmp, to: url)
        } catch {
            logger.warning("Failed to save grants for \(file.repoKey): \(error.localizedDescription)")
        }
    }

    // MARK: - Delete

    func delete(repoKey: String) {
        let url = fileURL(for: repoKey)
        _ = try? FileManager.default.removeItem(at: url)
    }

    func deleteAll() {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: grantsDir,
            includingPropertiesForKeys: nil
        ) else { return }
        for url in contents where url.pathExtension == "json" {
            _ = try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Helpers

    private func fileURL(for repoKey: String) -> URL {
        grantsDir.appendingPathComponent("\(repoKey).json")
    }

    private func quarantine(_ url: URL) {
        let broken = url.appendingPathExtension("broken")
        _ = try? FileManager.default.removeItem(at: broken)
        _ = try? FileManager.default.moveItem(at: url, to: broken)
    }
}

// MARK: - JSON formatter helpers

private extension JSONDecoder {
    static let iso8601: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

private extension JSONEncoder {
    static let iso8601Pretty: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}
