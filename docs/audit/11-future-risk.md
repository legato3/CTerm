# Phase 11: Future Risk (1-Year Projection)

Assumes active development on this fork for 12 months.

## What Will Become Painful

### 1. ✅ CalyxWindowController keeps growing — MITIGATED

8 extraction steps completed: TabCleanupHelper, GitController, ReviewController, FocusManager, typed notifications, WindowActions environment, BrowserManager, ComposeOverlayController. File is now ~1,900 lines. Remaining responsibilities: split operations, IPC enable/disable, review dispatch, tab/group lifecycle.

### 2. ✅ Ghostty submodule updates — MITIGATED

All 28 notification handlers now use typed event wrappers. A C API change that renames a `userInfo` key will be caught at the `from(_:)` factory and return `nil` — handler silently no-ops — rather than silently using wrong data. Still requires manual audit of `GhosttyFFI` and `SurfaceView` input handling on each update.

### 3. ✅ macOS API evolution — MITIGATED (focus management)

The timing-dependent polling loop was replaced with `SplitContainerView.onDeferredLayoutComplete` callback. Focus restoration no longer depends on undocumented layout timing. Remaining risks:
- New Glass APIs may require different view hierarchy structures
- Metal layer hosting rules may change

### 4. AI agent IPC expansion

The MCP server currently supports basic tool calls (8 tools). As AI coding tools evolve:
- More IPC capabilities needed (streaming, file transfer, workspace context)
- `CalyxWindowController.sendReviewToAgent()` is tightly coupled to the terminal surface
- Hard-coded timing delays (500ms) for paste confirmation won't work for all AI tools

### 5. ✅ Testing complexity — PARTIALLY MITIGATED

- `CalyxMCPServer._testSetToken()` `#if DEBUG` backdoor eliminated — replaced with `init(testToken:)`
- `CalyxWindowController` already accepts injected `mcpServer: CalyxMCPServer = .shared`
- Remaining: `GhosttyAppController.shared`, `ClaudeUsageMonitor.shared`, and 7 other singletons still require full app for testing

## What Will Break First

### ✅ Focus management — FIXED

~~The 500ms retry with 10ms backoff is timing-dependent.~~ Replaced with `SplitContainerView.onDeferredLayoutComplete` callback. Focus failures now show an amber border indicator and are logged at `warning` level.

### ✅ Session restore with new tab types — GUARDED

~~There's no test that verifies round-trip serialization for all tab types.~~ Tests `test_tabContent_terminal_roundtrip`, `test_tabContent_browser_roundtrip`, and `test_tabContent_diff_excluded_from_persistence` now guard against silent data loss. Adding a new persistable `TabContent` case still requires updating the snapshot codec; the tests will catch any missed step.

## What Will Slow Development

### Adding a new tab type

Current cost to add a tab type (e.g., "markdown preview"):
1. Add case to `TabContent` enum
2. Add snapshot encoding/decoding
3. Add restore logic in AppDelegate
4. Add view rendering in MainContentView
5. Add lifecycle management in CalyxWindowController (creation, activation, deactivation, cleanup)
6. ~~Thread callbacks through MainContentView's 22 closures~~ — now uses `WindowActions` environment object
7. Update `closeTab`, `closeActiveGroup`, `closeAllTabsInGroup`, `windowWillClose`

Steps 5 and 7 still touch the controller. This is now closer to half a day of focused work.

### Adding a new sidebar mode

Current cost: modify `SidebarMode` enum, add view in `SidebarContentView`, add handlers in `CalyxWindowController`. The `WindowActions` environment object has reduced callback churn here.

### ✅ Debugging notification-based bugs — IMPROVED

~~`userInfo` type mismatches fail silently at runtime.~~ All notification handlers now use typed event wrappers. A missing or renamed key now causes `from(_:)` to return `nil` at the factory boundary, not deep inside handler logic. Debugging narrows to: was the notification posted? Did `from(_:)` return nil?

## Fix NOW to Avoid Future Pain

### 1. ✅ Extract from CalyxWindowController (Priority: Critical) — DONE

Steps 1-8 completed: TabCleanupHelper, GitController, ReviewController, FocusManager, typed notifications, WindowActions environment, BrowserManager, ComposeOverlayController.

### 2. ✅ Type all notifications (Priority: High) — DONE

All 28 notification handlers now use typed event wrappers in `GhosttyNotificationEvents.swift`.

### 3. ✅ Add TabContent round-trip test (Priority: High) — DONE

Tests `test_tabContent_terminal_roundtrip`, `test_tabContent_browser_roundtrip`, and `test_tabContent_diff_excluded_from_persistence` in `SessionPersistenceTests.swift`.

### 4. ✅ Replace restoreFocus timing hack (Priority: Medium) — DONE

Polling loop replaced with `SplitContainerView.onDeferredLayoutComplete` callback.

### 5. ✅ Add dependency injection for testability (Priority: Medium) — DONE

`CalyxMCPServer._testSetToken()` `#if DEBUG` backdoor removed. Tests now use `CalyxMCPServer(testToken:)`. `CalyxWindowController` already accepts injected `mcpServer: CalyxMCPServer = .shared`. Pattern can be extended to other singletons as needed.
