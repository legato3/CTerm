// MemoryToastController.swift
// CTerm
//
// Shows brief toasts when agent memory is written during a session.
// "Learned: test-command → xcodebuild test -scheme CTermTests"
// Auto-dismisses after 3 seconds.

import Foundation
import Observation
import OSLog

private let logger = Logger(subsystem: "com.legato3.cterm", category: "MemoryToast")

struct MemoryToast: Identifiable, Sendable {
    let id: UUID
    let key: String
    let value: String
    let isNew: Bool
    let timestamp: Date

    init(key: String, value: String, isNew: Bool) {
        self.id = UUID()
        self.key = key
        self.value = value
        self.isNew = isNew
        self.timestamp = Date()
    }

    var displayText: String {
        let verb = isNew ? "Learned" : "Updated"
        let truncatedValue = value.count > 60 ? String(value.prefix(60)) + "…" : value
        return "\(verb): \(key) → \(truncatedValue)"
    }
}

@Observable
@MainActor
final class MemoryToastController {
    static let shared = MemoryToastController()

    /// The currently visible toast. Nil when no toast is showing.
    private(set) var activeToast: MemoryToast?

    /// Recent toasts for history (last 10).
    private(set) var recentToasts: [MemoryToast] = []

    private var dismissTask: Task<Void, Never>?
    private var observer: NSObjectProtocol?
    private static let displayDuration: UInt64 = 3_000_000_000 // 3s
    private static let maxHistory = 10

    private init() {}

    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .agentMemoryChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleMemoryChange()
            }
        }
    }

    func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
        dismissTask?.cancel()
    }

    func dismiss() {
        dismissTask?.cancel()
        activeToast = nil
    }

    // MARK: - Private

    private var lastKnownKeys: Set<String> = []

    private func handleMemoryChange() {
        guard UserDefaults.standard.bool(forKey: AppStorageKeys.memoryToastsEnabled) else { return }

        // Try to detect what changed by checking the most recent audit log entry
        let auditEntries = SessionAuditLogger.shared.recentEntries(ofType: .memoryWritten, limit: 1)
        guard let latest = auditEntries.first else { return }

        // Parse "key: value" from the audit detail
        let parts = latest.detail.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { return }
        let key = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        let value = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)

        let isNew = !lastKnownKeys.contains(key)
        lastKnownKeys.insert(key)

        show(key: key, value: value, isNew: isNew)
    }

    private func show(key: String, value: String, isNew: Bool) {
        let toast = MemoryToast(key: key, value: value, isNew: isNew)
        activeToast = toast
        recentToasts.insert(toast, at: 0)
        if recentToasts.count > Self.maxHistory {
            recentToasts = Array(recentToasts.prefix(Self.maxHistory))
        }

        logger.debug("MemoryToast: \(toast.displayText)")

        dismissTask?.cancel()
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.displayDuration)
            guard !Task.isCancelled else { return }
            self?.activeToast = nil
        }
    }
}
