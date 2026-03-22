# Phase 3: Data, State & Reliability

## Multiple Sources of Truth

### Tab title

Set via `handleSetTitleNotification` on the focused surface view, but only if that surface is the focused one in the active tab. Background tabs receiving title updates from ghostty are silently ignored. A user switching tabs may see stale titles.

```swift
// CalyxWindowController.swift:1188-1200
@objc private func handleSetTitleNotification(_ notification: Notification) {
    guard let surfaceView = notification.object as? SurfaceView else { return }
    guard belongsToThisWindow(surfaceView) else { return }
    guard let title = notification.userInfo?["title"] as? String else { return }
    guard let tab = activeTab else { return }

    if let focusedID = tab.splitTree.focusedLeafID,
       let focusedView = tab.registry.view(for: focusedID),
       focusedView === surfaceView {
        window?.title = title   // Only updates if surface is focused
        tab.title = title
    }
}
```

### Window title vs Tab title

`window?.title` and `tab.title` are set together in `handleSetTitleNotification`, but only from the active tab's focused surface. If you have splits, non-focused panes changing their title won't update anything.

### Browser URL

Stored in `tab.content = .browser(url:)` AND in `browserController.browserState.url`. The snapshot reads from the controller first, falling back to the tab content. Navigation in the browser updates both, but there's a window where they diverge.

```swift
// CalyxWindowController.swift:1392
browserURL = browserControllers[tab.id]?.browserState.url ?? configuredURL
```

### `hasMoreCommits` flag

Lives as a bare `Bool` on `CalyxWindowController`, not on the git model. If you have two views showing git state, this flag isn't shared.

## State Duplication

- `windowSession.sidebarMode` is duplicated via the `Binding` passed to `MainContentView`
- `activeBrowserController`, `activeDiffState`, `activeDiffSource`, `activeDiffReviewStore` are computed properties on the controller AND stored on `WindowViewState`. The controller manually syncs them via `updateViewState()`.

## Race Condition Risks

### 1. Spin-loop in applicationWillTerminate

```swift
// AppDelegate.swift:116-126
var done = false
Task {
    await SessionPersistenceActor.shared.saveImmediately(snapshot)
    await SessionPersistenceActor.shared.resetRecoveryCounter()
    done = true
}
let deadline = Date().addingTimeInterval(1.0)
while !done, Date() < deadline {
    RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
}
```

This pattern appears in 3 places (`applicationWillTerminate`, `saveImmediately`, `restoreSession`). It blocks the main thread waiting for an actor. If the save takes >1-2 seconds, the app terminates without saving. If the RunLoop processes UI events during the spin, re-entrant calls could corrupt state.

### 2. restoreFocus retry loop

`attemptFocusRestore` retries every 10ms for 500ms. If the view hierarchy is slow to attach (e.g., complex SwiftUI layout), this silently gives up and registers a deferred callback that might never fire.

```swift
// CalyxWindowController.swift:946-984
private func attemptFocusRestore(requestID: UInt64, startTime: Double) {
    guard requestID == focusRequestID else { return }
    let elapsed = CACurrentMediaTime() - startTime
    // ...
    guard elapsed < Self.focusRestoreTimeout else {
        splitContainerView?.onDeferredLayoutComplete = { ... }
        return  // Gives up after 500ms
    }
    // Retry with 10ms backoff
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { ... }
}
```

### 3. sendComposeText / sendReviewToAgent timing

Uses `DispatchQueue.main.asyncAfter(deadline: .now() + 0.5)` for key event delays. These are fragile timing assumptions -- if the terminal is slow (e.g., processing a large paste), the Enter key arrives too early or too late.

```swift
// CalyxWindowController.swift:909-923
if isAgent {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        // First Enter (confirm paste)
        controller.sendKey(keyEvent)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Second Enter (submit)
            controller.sendKey(keyEvent)
        }
    }
}
```

## UI Desync Scenarios

### Tab close during surface notification

`closingTabIDs` set prevents double-close, but if a `handleCloseSurfaceNotification` arrives between `closingTabIDs.insert` and the actual surface destruction, the notification handler returns early. This is correct but makes the flow hard to reason about.

### Diff tab persistence gap

Diff tabs are explicitly excluded from session snapshots:

```swift
if case .diff = tab.content { return nil }
```

If the app crashes while viewing a diff, the tab is lost. The user might expect it to be restored.

## Concrete Fixes

### 1. Replace spin-loops with proper async patterns

Instead of `while !done` in `applicationWillTerminate`, rely on the debounced saves that already run on every state change (`requestSave()`). Make the terminate-time save best-effort. The crash-loop detection already handles the failure case.

### 2. Type-safe notifications

Create typed notification wrappers that validate payloads at the posting site:

```swift
struct GhosttyNewSplitEvent {
    let surfaceView: SurfaceView
    let direction: ghostty_action_split_direction_e
    let inheritedConfig: ghostty_surface_config_s?
}
```

### 3. Consolidate WindowViewState sync

Make `WindowViewState` compute its values directly from the `WindowSession` rather than being manually copied. Or use a `didSet` observer on `activeTabID` to trigger automatic sync.

### 4. Fix title updates for background tabs

Store titles per-surface (in `SurfaceRegistry` or `SurfaceView`), not just for the focused surface. When switching tabs, read the title from the newly-focused surface.
