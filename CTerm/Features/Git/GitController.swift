import OSLog

private let gitLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.legato3.cterm",
    category: "GitController"
)

/// Manages git state refresh, commit log pagination, and diff navigation.
/// Owned by CTermWindowController; communicates back via callbacks.
@MainActor
final class GitController {
    // MARK: - State

    private var refreshTask: Task<Void, Never>?
    private var loadMoreTask: Task<Void, Never>?
    private var expandTasks: [String: Task<Void, Never>] = [:]
    private var hasMoreCommits = true

    // MARK: - Dependencies

    private weak var windowSession: WindowSession?

    /// Called when a working-tree or commit file selection should open a diff tab.
    var onOpenDiff: ((DiffSource) -> Void)?

    // MARK: - Init

    init(windowSession: WindowSession) {
        self.windowSession = windowSession
    }

    // MARK: - Public API

    func cancelAll() {
        refreshTask?.cancel()
        loadMoreTask?.cancel()
        for (_, task) in expandTasks { task.cancel() }
        expandTasks.removeAll()
    }

    // MARK: - Git Operations

    func refreshGitStatus() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            guard let windowSession = self.windowSession else { return }

            let workDir = self.findWorkDir()
            guard let workDir else {
                windowSession.git.changesState = .error("No working directory found")
                return
            }

            windowSession.git.changesState = .loading

            do {
                let repoRoot = try await GitService.repoRoot(workDir: workDir)
                guard !Task.isCancelled else { return }

                windowSession.git.repoRoots[workDir] = repoRoot

                async let statusResult = GitService.gitStatus(workDir: repoRoot)
                async let logResult = GitService.commitLog(workDir: repoRoot, maxCount: 100, skip: 0)

                let (entries, commits) = try await (statusResult, logResult)
                guard !Task.isCancelled else { return }

                windowSession.git.entries = entries
                windowSession.git.commits = commits
                self.hasMoreCommits = true
                windowSession.git.expandedCommitIDs = []
                windowSession.git.commitFiles = [:]
                windowSession.git.changesState = .loaded
            } catch let error as GitService.GitError {
                guard !Task.isCancelled else { return }
                if case .notARepository = error {
                    windowSession.git.changesState = .notRepository
                } else {
                    windowSession.git.changesState = .error(error.localizedDescription)
                }
            } catch {
                guard !Task.isCancelled else { return }
                windowSession.git.changesState = .error(error.localizedDescription)
            }
        }
    }

    func loadMoreCommits() {
        guard hasMoreCommits else { return }
        guard loadMoreTask == nil || loadMoreTask?.isCancelled == true else { return }
        loadMoreTask = Task { [weak self] in
            guard let self else { return }
            guard let windowSession = self.windowSession else { return }
            let currentCount = windowSession.git.commits.count

            guard let workDir = self.findWorkDir(),
                  let repoRoot = windowSession.git.repoRoots[workDir] else { return }

            do {
                let moreCommits = try await GitService.commitLog(
                    workDir: repoRoot, maxCount: 50, skip: currentCount
                )
                guard !Task.isCancelled else { return }
                guard !moreCommits.isEmpty else {
                    self.hasMoreCommits = false
                    return
                }
                windowSession.git.commits.append(contentsOf: moreCommits)
            } catch {
                gitLogger.warning("Failed to load more commits: \(error.localizedDescription)")
            }
            self.loadMoreTask = nil
        }
    }

    func expandCommit(hash: String) {
        guard let windowSession else { return }

        if windowSession.git.expandedCommitIDs.contains(hash) {
            windowSession.git.expandedCommitIDs.remove(hash)
            return
        }

        windowSession.git.expandedCommitIDs.insert(hash)

        if windowSession.git.commitFiles[hash] != nil { return }

        guard let workDir = findWorkDir(),
              let repoRoot = windowSession.git.repoRoots[workDir] else { return }

        expandTasks[hash] = Task { [weak self] in
            guard let self else { return }
            do {
                let files = try await GitService.commitFiles(hash: hash, workDir: repoRoot)
                self.windowSession?.git.commitFiles[hash] = files
            } catch {
                gitLogger.warning("Failed to expand commit \(hash): \(error.localizedDescription)")
            }
            self.expandTasks.removeValue(forKey: hash)
        }
    }

    func handleWorkingFileSelected(_ entry: GitFileEntry) {
        guard let windowSession else { return }
        guard let workDir = findWorkDir(),
              let repoRoot = windowSession.git.repoRoots[workDir] else { return }

        let source: DiffSource
        if entry.isStaged {
            source = .staged(path: entry.path, workDir: repoRoot)
        } else if entry.status == .untracked {
            source = .untracked(path: entry.path, workDir: repoRoot)
        } else {
            source = .unstaged(path: entry.path, workDir: repoRoot)
        }

        onOpenDiff?(source)
    }

    func handleCommitFileSelected(_ entry: CommitFileEntry) {
        guard let windowSession else { return }
        guard let workDir = findWorkDir(),
              let repoRoot = windowSession.git.repoRoots[workDir] else { return }

        let source: DiffSource = .commit(hash: entry.commitHash, path: entry.path, workDir: repoRoot)
        onOpenDiff?(source)
    }

    // MARK: - Private

    func findWorkDir() -> String? {
        guard let windowSession else { return nil }
        // 1. Active terminal tab's pwd
        if let tab = windowSession.activeGroup?.activeTab, case .terminal = tab.content, let pwd = tab.pwd {
            return pwd
        }
        // 2. Any terminal tab in same group
        if let group = windowSession.activeGroup {
            for tab in group.tabs {
                if case .terminal = tab.content, let pwd = tab.pwd { return pwd }
            }
        }
        // 3. Any terminal tab in any group
        for group in windowSession.groups {
            for tab in group.tabs {
                if case .terminal = tab.content, let pwd = tab.pwd { return pwd }
            }
        }
        // 4. Fallback from cached repo roots
        return windowSession.git.repoRoots.values.first
    }
}
