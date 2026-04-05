// AccessibilityID.swift
// CTerm
//
// Stable accessibility identifiers for XCUITest element lookup.

import Foundation

enum AccessibilityID {
    enum Sidebar {
        static let container = "cterm.sidebar"
        static let newGroupButton = "cterm.sidebar.newGroupButton"
        static func group(_ id: UUID) -> String { "cterm.sidebar.group.\(id.uuidString)" }
        static func tab(_ id: UUID) -> String { "cterm.sidebar.tab.\(id.uuidString)" }
        static func groupNameTextField(_ id: UUID) -> String { "cterm.sidebar.groupNameTextField.\(id.uuidString)" }
        static func groupCollapseButton(_ id: UUID) -> String { "cterm.sidebar.groupCollapseButton.\(id.uuidString)" }
        static func tabCloseButton(_ id: UUID) -> String { "cterm.sidebar.tab.\(id.uuidString).closeButton" }
        static func groupCloseAllButton(_ id: UUID) -> String { "cterm.sidebar.group.\(id.uuidString).closeAllButton" }
        static func tabNameTextField(_ id: UUID) -> String { "cterm.sidebar.tabNameTextField.\(id.uuidString)" }
        static func tabAtIndex(_ groupID: UUID, _ index: Int) -> String {
            "cterm.sidebar.group.\(groupID.uuidString).tab.index.\(index)"
        }
    }
    enum TabBar {
        static let container = "cterm.tabBar"
        static let newTabButton = "cterm.tabBar.newTabButton"
        static func tab(_ id: UUID) -> String { "cterm.tabBar.tab.\(id.uuidString)" }
        static func tabCloseButton(_ id: UUID) -> String { "cterm.tabBar.tab.\(id.uuidString).closeButton" }
        static func tabNameTextField(_ id: UUID) -> String { "cterm.tabBar.tabNameTextField.\(id.uuidString)" }
        static func tabAtIndex(_ index: Int) -> String { "cterm.tabBar.tab.index.\(index)" }
    }
    enum CommandPalette {
        static let container = "cterm.commandPalette"
        static let searchField = "cterm.commandPalette.searchField"
        static let resultsTable = "cterm.commandPalette.resultsTable"
    }
    enum Compose {
        static let container = "cterm.compose"
        static let textView = "cterm.compose.textView"
        static let placeholder = "cterm.compose.placeholder"
    }
    enum Search {
        static let container = "cterm.search"
        static let searchField = "cterm.search.searchField"
        static let matchCount = "cterm.search.matchCount"
        static let previousButton = "cterm.search.previousButton"
        static let nextButton = "cterm.search.nextButton"
        static let closeButton = "cterm.search.closeButton"
    }
    enum Browser {
        static let toolbar = "cterm.browser.toolbar"
        static let backButton = "cterm.browser.backButton"
        static let forwardButton = "cterm.browser.forwardButton"
        static let reloadButton = "cterm.browser.reloadButton"
        static let urlDisplay = "cterm.browser.urlDisplay"
        static let errorBanner = "cterm.browser.errorBanner"
    }
    enum Git {
        static let changesContainer = "cterm.git.changes"
        static let refreshButton = "cterm.git.refreshButton"
        static let modeToggle = "cterm.git.modeToggle"
        static let stagedSection = "cterm.git.staged"
        static let unstagedSection = "cterm.git.unstaged"
        static let untrackedSection = "cterm.git.untracked"
        static let commitsSection = "cterm.git.commits"
        static func fileEntry(_ path: String) -> String { "cterm.git.file.\(path)" }
        static func commitRow(_ hash: String) -> String { "cterm.git.commit.\(hash)" }
    }
    enum Diff {
        static let container = "cterm.diff"
        static let toolbar = "cterm.diff.toolbar"
        static let content = "cterm.diff.content"
        static let lineNumberGutter = "cterm.diff.lineNumbers"
    }
    enum DiffReview {
        static let submitButton = "cterm.diff.review.submitButton"
        static let discardButton = "cterm.diff.review.discardButton"
        static let commentBadge = "cterm.diff.review.commentBadge"
        static let commentPopover = "cterm.diff.review.commentPopover"
        static let submitAllButton = "cterm.diff.review.submitAllButton"
        static let discardAllButton = "cterm.diff.review.discardAllButton"
    }
}
