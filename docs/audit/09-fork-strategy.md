# Phase 9: Fork Strategy

This is now an independent fork. Based on this codebase, here is what to preserve, replace, and avoid.

## Preserve As-Is

### GhosttyFFI layer
Clean, minimal, correctly centralized. All C function calls go through this single `enum`. Don't add business logic here. 417 lines of pure wrapper methods.

### SplitTree
Excellent immutable value-type design. `Codable`, `Equatable`, `Sendable` struct with pure functions. Well-tested (561 lines of tests). The binary tree model with spatial navigation is elegant.

### Model hierarchy (AppSession -> WindowSession -> TabGroup -> Tab)
Simple, correct, `@Observable`. Each model is small (23-68 lines). ID-based selection is safe. Tab groups with colors are a good organizational model.

### SessionPersistenceActor
Proper actor isolation, atomic writes with temp+rename, backup rotation, crash-loop detection with recovery counter. Production-quality persistence. 163 lines, well-tested (592 lines of tests).

### SurfaceRegistry
Clean lifecycle management with drag-aware deferred destruction. Entry states (`creating`, `attached`, `detaching`, `destroyed`) prevent double-free. 155 lines.

### IPC/MCP protocol
Well-designed with proper JSON-RPC 2.0, typed request/response, actor-based message store with TTL. Comprehensive tests (614 + 486 + 479 lines).

## Gradually Replace

### NotificationCenter event bus -> Typed event system

The 28 untyped notifications are the biggest maintenance burden. Migrate one at a time, starting with the most-used:

1. `.ghosttyCloseSurface` (most critical -- drives tab lifecycle)
2. `.ghosttyNewSplit` (split creation)
3. `.ghosttySetTitle` (title updates)
4. `.ghosttySetPwd` (working directory tracking)
5. `.ghosttyGotoSplit` (focus navigation)

Use typed structs with factory methods (see fragility-map.md for pattern).

### CTermWindowController god class -> Focused controllers

Extract into:
- `GitController` (~200 lines: git status, commit history, diff loading)
- `ReviewController` (~150 lines: review stores, submission, discard)
- `FocusManager` (~100 lines: focus restore, retry loop)
- `BrowserTabManager` (~50 lines: browser tab lifecycle)

Keep the shell thin -- just delegation and routing.

### Callback-closure architecture in MainContentView -> Environment actions

Replace 22+ closures with `@Environment` action objects:

```swift
@Observable class WindowActions {
    var onTabSelected: ((UUID) -> Void)?
    var onCloseTab: ((UUID) -> Void)?
    // ... etc
}
// Pass via .environment() instead of 22 init parameters
```

### GCD-based GitService -> Pure async/await

Replace `DispatchSemaphore` + `withCheckedThrowingContinuation` with `Process` async support or `AsyncStream`.

## Avoid

### Do not try to replace the ghostty submodule
It's the rendering engine. You depend on it. Pin to a known-good commit and update deliberately.

### Do not introduce Combine
The codebase uses `@Observable` (Swift 5.9+), which is the successor. Adding Combine would create two reactive systems.

### Do not add SwiftData
Session persistence is file-based JSON and works well. SwiftData would be over-engineering for what is essentially "save/restore a tree of UUIDs."

### Do not convert AppKit window management to SwiftUI
`NSWindowController` + `NSHostingView` is the correct pattern for this app. Pure SwiftUI window management lacks the control needed for a terminal (first responder management, Metal layer hosting, CGEvent tap).

### Do not add a TOML/YAML parser dependency just for CodexConfigManager
The hand-coded regex parser has 520 lines of tests. It's good enough. A dependency would add more risk than it removes.

## Roadmap

### Phase 1: Stabilize (Weeks 1-4)

| Task | Effort | Impact |
|------|--------|--------|
| Extract tab cleanup helper | 1 hour | Eliminates 4x duplication |
| Fix BrowserServer token generation | 15 min | Security fix |
| Add logging to silent catch blocks | 15 min | Debuggability |
| Delete unused notification names (after grep) | 1 hour | Reduce noise |
| Move performDebugSelect behind #if DEBUG | 30 min | Clean production code |
| Write ARCHITECTURE.md documenting current system | 2 hours | Onboarding |
| Run full test suite, fix any failures | 2 hours | Baseline confidence |
| Pin ghostty submodule to known-good commit | 15 min | Stability |
| Extract generateHexToken utility | 30 min | DRY security code |
| Add reverse lookup to findTab | 1 hour | Performance |

### Phase 2: Improve (Months 2-3)

| Task | Effort | Impact |
|------|--------|--------|
| Extract GitController from CTermWindowController | 1 day | -200 lines from god class |
| Extract ReviewController | 1 day | -150 lines from god class |
| Extract FocusManager | 0.5 day | -100 lines, cleaner focus logic |
| Type top 5 notifications | 2 days | Compile-time safety |
| Replace GitService GCD with async Process | 1 day | Cleaner concurrency |
| Add session save/restore round-trip test | 0.5 day | Catch serialization bugs |
| Reduce MainContentView callbacks | 1 day | Simpler view hierarchy |

### Phase 3: Evolve (Months 4-12)

| Task | Effort | Impact |
|------|--------|--------|
| Complete notification -> typed events migration | 2 weeks | Full compile-time safety |
| CTermWindowController below 500 lines | 1 week | Maintainable core |
| Add error recovery UI (toast/banner) | 1 week | Better UX for git/network errors |
| Consider plugin architecture for features | Design phase | Extensibility |
| Evaluate NWListener replacement options | Research | Simplify HTTP servers |
| Multi-window session sharing | Design phase | Power user feature |
