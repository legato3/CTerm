# Phase 11: Future Risk (1-Year Projection)

Assumes active development on this fork for 12 months.

## What Will Become Painful

### 1. CalyxWindowController keeps growing

Every new feature (AI integrations, new tab types, workspace features) adds code here. At 1,965 lines today, expect 3,000+ in a year without extraction. Effects:
- Merge conflicts on every PR that touches window behavior
- Increasing cognitive load -- understanding one feature requires reading 2,000 lines of context
- Test isolation becomes impossible -- can't test git logic without instantiating the full window controller

### 2. Ghostty submodule updates

libghostty is actively developed. C API changes will require updating:
- `GhosttyFFI` (all wrapper methods)
- All 10 notification handlers in CalyxWindowController
- `SurfaceView` input handling
- `GhosttyConfig` key loading

Without typed events, each update is a manual audit of 28 notification paths. A single missed `userInfo` key change causes silent feature breakage.

### 3. macOS API evolution

Apple is pushing SwiftUI and Liquid Glass APIs forward. The `NSHostingView` bridge works but:
- macOS 27 SwiftUI changes could affect layout timing, breaking the focus management retry loop
- New Glass APIs may require different view hierarchy structures
- Metal layer hosting rules may change

### 4. AI agent IPC expansion

The MCP server currently supports basic tool calls (8 tools). As AI coding tools evolve:
- More IPC capabilities needed (streaming, file transfer, workspace context)
- `CalyxWindowController.sendReviewToAgent()` is tightly coupled to the terminal surface
- Hard-coded timing delays (500ms) for paste confirmation won't work for all AI tools

### 5. Testing complexity

10 singletons with `static let shared` make unit testing require `#if DEBUG` escape hatches. As the app grows:
- New features that depend on `GhosttyAppController.shared` can't be tested without the full app
- `CalyxMCPServer.shared` requires `_testSetToken()` backdoor
- Test parallelism is impossible (singletons share global state)

## What Will Break First

### Focus management

The 500ms retry with 10ms backoff is timing-dependent. A macOS update that changes SwiftUI layout scheduling will break this silently. Symptom: terminal appears but doesn't accept keyboard input. This is the most likely user-facing regression because:
- It depends on undocumented SwiftUI layout timing
- There's no diagnostic logging for the failure path
- The deferred callback fallback has a race condition

### Session restore with new tab types

Adding any new `TabContent` case requires updating:
- `TabContent` enum
- `SessionSnapshot` / `WindowSnapshot` / `TabSnapshot`
- `restoreWindow()` in AppDelegate
- `windowSnapshot()` in CalyxWindowController
- JSON codec (both encode and decode)

Missing any one causes silent data loss. The tab appears to close but is actually not persisted. There's no test that verifies round-trip serialization for all tab types.

## What Will Slow Development

### Adding a new tab type

Current cost to add a tab type (e.g., "markdown preview"):
1. Add case to `TabContent` enum
2. Add snapshot encoding/decoding
3. Add restore logic in AppDelegate
4. Add view rendering in MainContentView
5. Add lifecycle management in CalyxWindowController (creation, activation, deactivation, cleanup)
6. Thread callbacks through MainContentView's 22 closures
7. Update `closeTab`, `closeActiveGroup`, `closeAllTabsInGroup`, `windowWillClose`

Steps 5-7 all touch the god class. This is at least a full day of work for what should be a modular feature.

### Adding a new sidebar mode

Current cost: modify `SidebarMode` enum, add view in `SidebarContentView` (626 lines), add callbacks through `MainContentView`, add handlers in `CalyxWindowController`. The callback chain makes simple features feel heavy.

### Debugging notification-based bugs

When something stops working (titles not updating, splits not creating), the debugging process is:
1. Set breakpoint in notification handler
2. Verify notification is posted (go to GhosttyApp.swift callback)
3. Verify `userInfo` has expected keys and types
4. Verify `as?` cast succeeds
5. Verify `belongsToThisWindow` returns true
6. Verify `activeTab` is non-nil

This takes 30+ minutes per bug. With typed events, most of these steps are compile-time errors.

## Fix NOW to Avoid Future Pain

### 1. Extract from CalyxWindowController (Priority: Critical)

The git/diff/review controllers described in the refactor plan (Phase 10, Steps 2-4). Do this before adding any new features. Every week of delay makes the extraction harder because new code gets added to the god class.

### 2. Type the top 5 notifications (Priority: High)

`.ghosttyNewSplit`, `.ghosttyCloseSurface`, `.ghosttySetTitle`, `.ghosttySetPwd`, `.ghosttyGotoSplit`. These are the most-used and most-fragile notification paths. Adding type safety here catches the most common class of bugs.

### 3. Add TabContent round-trip test (Priority: High)

A test that verifies every `TabContent` case can be encoded -> decoded -> restored:

```swift
func testAllTabContentTypesRoundTrip() {
    let cases: [TabContent] = [
        .terminal,
        .browser(url: URL(string: "https://example.com")!),
        // .diff is excluded from persistence (by design)
    ]
    for content in cases {
        let tab = Tab(content: content)
        let snapshot = TabSnapshot(from: tab)
        let data = try! JSONEncoder().encode(snapshot)
        let restored = try! JSONDecoder().decode(TabSnapshot.self, from: data)
        // Verify restored content matches original
    }
}
```

This catches silent data loss when adding new tab types.

### 4. Replace restoreFocus timing hack (Priority: Medium)

Use `NSView.viewDidMoveToWindow` or `viewDidLayout` callbacks instead of polling:

```swift
// Instead of 10ms retry loop:
surfaceView.onReadyForFocus = { [weak self] in
    self?.window?.makeFirstResponder(surfaceView)
}
```

This survives macOS layout timing changes and eliminates the 500ms timeout race.

### 5. Add dependency injection for testability (Priority: Medium)

Start with one singleton: `CalyxMCPServer`. Instead of `.shared`, inject it:

```swift
init(mcpServer: CalyxMCPServer = .shared) {
    self.mcpServer = mcpServer
}
```

This pattern can be gradually extended to other singletons as tests require it.
