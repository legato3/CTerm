// SlashPopoverCoordinator.swift
// CTerm
//
// Shared state bridge between the SwiftUI-hosted slash-command popover
// (owned by `MainContentView`) and the AppKit `ComposeTextView` that
// receives key events. Mirrors BlockMentionPopoverCoordinator — the
// popover writes `isShowing`, `itemCount`, and callbacks; the text view
// reads `isShowing`/`itemCount` and mutates `selectedIndex` in response
// to arrow keys, then fires `onSelect`/`onDismiss` on Enter/Escape.

import Foundation

@Observable
@MainActor
final class SlashPopoverCoordinator {
    var isShowing: Bool = false
    var itemCount: Int = 0
    var selectedIndex: Int = 0
    var onSelect: ((Int) -> Void)?
    var onDismiss: (() -> Void)?

    func clampSelection() {
        guard itemCount > 0 else {
            selectedIndex = 0
            return
        }
        if selectedIndex < 0 { selectedIndex = 0 }
        if selectedIndex > itemCount - 1 { selectedIndex = itemCount - 1 }
    }

    func moveDown() {
        guard itemCount > 0 else { return }
        selectedIndex = min(itemCount - 1, selectedIndex + 1)
    }

    func moveUp() {
        guard itemCount > 0 else { return }
        selectedIndex = max(0, selectedIndex - 1)
    }

    func resetSelection(itemCount: Int) {
        self.itemCount = itemCount
        self.selectedIndex = 0
    }
}
