# Phase 5: Performance & Responsiveness

## Main Thread Blocking

### 1. Synchronous spin-loops

`applicationWillTerminate` and `restoreSession` both block the main thread:

```swift
// AppDelegate.swift:122-125
let deadline = Date().addingTimeInterval(1.0)
while !done, Date() < deadline {
    RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
}
```

This pattern appears 3 times, blocking for up to 1-2 seconds each. During session restore, the UI is frozen while waiting for the persistence actor.

### 2. findTab(for:) linear scan

Called on every notification handler. Scans all groups -> all tabs -> all registry entries:

```swift
// CalyxWindowController.swift:1437-1446
private func findTab(for surfaceView: SurfaceView) -> (Tab, TabGroup)? {
    for group in windowSession.groups {
        for tab in group.tabs {
            if tab.registry.id(for: surfaceView) != nil {
                return (tab, group)
            }
        }
    }
    return nil
}
```

With many tabs, this is O(n^2) per notification since `registry.id(for:)` does a linear scan of the entries dictionary.

### 3. Repeated flat scans

`jumpToMostRecentUnreadTab`, `totalReviewCommentCount`, `reviewFileCount`, `configStatusMessage` all independently scan all groups x all tabs. Fine for small tab counts but repeated on every state change.

## Unnecessary Re-renders

### 1. refreshHostingView() sets all properties

```swift
// CalyxWindowController.swift:419-426
private func updateViewState() {
    windowViewState.activeBrowserController = activeBrowserController
    windowViewState.activeDiffState = activeDiffState
    windowViewState.activeDiffSource = activeDiffSource
    windowViewState.activeDiffReviewStore = activeDiffReviewStore
    windowViewState.totalReviewCommentCount = totalReviewCommentCount
    windowViewState.reviewFileCount = reviewFileCount
}
```

Since `WindowViewState` is `@Observable`, setting any property triggers SwiftUI observation. Setting unchanged reference types (like `DiffReviewStore`) still triggers re-evaluation.

### 2. MainContentView.body reads many sources

The body reads `windowSession.groups`, `activeGroup.tabs`, `activeGroup.activeTabID`, `sidebarMode`, `glassOpacity`, `themePreset`, `customHex`, `ghosttyProvider.ghosttyBackground`. Any change to any of these re-evaluates the entire view body including gradient computations.

## Memory / Allocation Concerns

### SplitTree.allLeafIDs() array allocation

Allocates new arrays via concatenation (`+`) on every call:

```swift
private static func collectLeaves(_ node: SplitNode) -> [UUID] {
    switch node {
    case .leaf(let id):
        return [id]
    case .split(let data):
        return collectLeaves(data.first) + collectLeaves(data.second)
    }
}
```

Called from `focusTarget`, `remove`, `restoreTabSurfaces`. For deep trees, this creates O(n) intermediate arrays that are immediately discarded.

## What Would Feel Slow to a User

| Scenario | Cause | Impact |
|----------|-------|--------|
| Session restore with 20+ tabs | Each tab creates a Metal surface via C calls + spin-loop wait | Multi-second launch freeze |
| Opening many git diffs quickly | Each diff spawns a `git diff` process | Queued process spawns |
| Many tabs + frequent notifications | `findTab(for:)` linear scan per notification | Cumulative UI lag |
| Theme/opacity change | Full MainContentView re-render with gradient recomputation | Momentary stutter |

## What Will Not Scale

| Component | Current | At Scale |
|-----------|---------|----------|
| `findTab(for:)` | O(n^2) per notification | Unusable with 50+ tabs |
| Session restore | Sequential surface creation | Minutes with 100+ tabs |
| Git commit log | Loads 100 commits initially | Fine for now, pagination exists |
| NotificationCenter | All windows receive all notifications | Unnecessary processing in multi-window |

## Highest-Impact Improvements

### 1. Add reverse lookup to findTab (High impact, low effort)

Add `surfaceViewToTab: [ObjectIdentifier: (Tab, TabGroup)]` dictionary, maintained on surface creation/destruction. Turns O(n^2) into O(1).

### 2. Lazy allLeafIDs() (Medium impact, low effort)

Return a `LazySequence` or use an `inout [UUID]` accumulator instead of array concatenation:

```swift
private static func collectLeaves(_ node: SplitNode, into result: inout [UUID]) {
    switch node {
    case .leaf(let id): result.append(id)
    case .split(let data):
        collectLeaves(data.first, into: &result)
        collectLeaves(data.second, into: &result)
    }
}
```

### 3. Batch updateViewState() (Medium impact, low effort)

Only set properties that actually changed. Use reference equality for reference types:

```swift
let newController = activeBrowserController
if newController !== windowViewState.activeBrowserController {
    windowViewState.activeBrowserController = newController
}
```

### 4. Filter notifications by window (Medium impact, medium effort)

Each notification handler calls `belongsToThisWindow(surfaceView)` after the scan. Instead, scope notification observers to their own window's surface views.

### 5. Parallelize session restore (High impact, medium effort)

Create surfaces concurrently where possible rather than sequentially looping through tabs.
