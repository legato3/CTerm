import AppKit

/// Manages diff tab state, review comment stores, and review submission.
/// Owned by CalyxWindowController; communicates back via callbacks.
@MainActor
final class ReviewController {
    // MARK: - State

    private(set) var diffStates: [UUID: DiffLoadState] = [:]
    private(set) var reviewStores: [UUID: DiffReviewStore] = [:]
    private var diffTasks: [UUID: Task<Void, Never>] = [:]

    // MARK: - Dependencies

    private weak var windowSession: WindowSession?

    /// Called when diff load state changes (triggers refreshHostingView).
    var onDiffStateChanged: (() -> Void)?

    /// Called when review comments change (triggers generation increment + updateViewState).
    var onReviewChanged: (() -> Void)?

    /// Called to send a review payload to an AI agent terminal; returns the send result.
    var sendToAgent: ((String) -> ReviewSendResult)?

    // MARK: - Computed

    var totalReviewCommentCount: Int {
        reviewStores.values.filter { $0.hasUnsubmittedComments }.reduce(0) { $0 + $1.comments.count }
    }

    var reviewFileCount: Int {
        reviewStores.values.filter { $0.hasUnsubmittedComments }.count
    }

    // MARK: - Init

    init(windowSession: WindowSession) {
        self.windowSession = windowSession
    }

    // MARK: - Lifecycle

    func loadDiff(tabID: UUID, source: DiffSource) {
        diffStates[tabID] = .loading

        let reviewStore = DiffReviewStore()
        reviewStore.onCommentsChanged = { [weak self] in
            self?.onReviewChanged?()
        }
        reviewStores[tabID] = reviewStore

        diffTasks[tabID] = Task { [weak self] in
            guard let self else { return }
            guard let windowSession = self.windowSession else { return }
            do {
                let rawDiff = try await GitService.fileDiff(source: source)
                guard !Task.isCancelled else { return }

                let path: String
                switch source {
                case .unstaged(let p, _), .staged(let p, _), .commit(_, let p, _), .untracked(let p, _):
                    path = p
                case .allChanges:
                    path = "all"
                }
                let parsed = DiffParser.parse(rawDiff, path: path)
                guard !Task.isCancelled else { return }

                guard windowSession.groups.flatMap(\.tabs).contains(where: { $0.id == tabID }) else { return }

                self.diffStates[tabID] = .success(parsed)
                self.onDiffStateChanged?()
            } catch {
                guard !Task.isCancelled else { return }
                self.diffStates[tabID] = .error(error.localizedDescription)
                self.onDiffStateChanged?()
            }
        }
    }

    func cleanupTab(id tabID: UUID) {
        diffTasks[tabID]?.cancel()
        diffTasks.removeValue(forKey: tabID)
        diffStates.removeValue(forKey: tabID)
        reviewStores.removeValue(forKey: tabID)
    }

    func cancelAll() {
        for (_, task) in diffTasks { task.cancel() }
        diffTasks.removeAll()
        diffStates.removeAll()
        reviewStores.removeAll()
    }

    // MARK: - Review Submission

    func submitDiffReview(tabID: UUID) {
        guard let windowSession else { return }
        guard let store = reviewStores[tabID], store.hasUnsubmittedComments else { return }

        guard let tab = windowSession.groups.flatMap(\.tabs).first(where: { $0.id == tabID }),
              case .diff(let source) = tab.content else { return }
        let filePath: String
        switch source {
        case .unstaged(let p, _), .staged(let p, _), .commit(_, let p, _), .untracked(let p, _):
            filePath = p
        case .allChanges:
            filePath = "all"
        }

        let payload = store.formatForSubmission(filePath: filePath)
        let result = sendToAgent?(payload) ?? .failed

        if result == .sent {
            store.clearAll()
            onDiffStateChanged?()
        }
    }

    func submitAllDiffReviews() {
        guard let windowSession else { return }
        let entries: [(source: DiffSource, store: DiffReviewStore)] = reviewStores.compactMap { tabID, store in
            guard store.hasUnsubmittedComments else { return nil }
            guard let tab = windowSession.groups.flatMap(\.tabs).first(where: { $0.id == tabID }),
                  case .diff(let source) = tab.content else { return nil }
            return (source: source, store: store)
        }
        guard !entries.isEmpty else { return }

        let payload = DiffReviewStore.formatAllForSubmission(entries)
        let result = sendToAgent?(payload) ?? .failed

        if result == .sent {
            for entry in entries { entry.store.clearAll() }
            onDiffStateChanged?()
        }
    }

    func discardAllDiffReviews() {
        let storesWithComments = reviewStores.values.filter { $0.hasUnsubmittedComments }
        guard !storesWithComments.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "Discard All Review Comments"
        alert.informativeText = "This will discard \(totalReviewCommentCount) comment(s) across \(reviewFileCount) file(s)."
        alert.addButton(withTitle: "Discard All")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        for store in storesWithComments { store.clearAll() }
        onDiffStateChanged?()
    }
}
