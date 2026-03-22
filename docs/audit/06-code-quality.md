# Phase 6: Code Quality & Tech Debt

## Safety Record

| Metric | Production Code | Test Code |
|--------|----------------|-----------|
| Force unwraps (`!`) | 0 | Common (acceptable) |
| Force casts (`as!`) | 0 | ~10 (acceptable) |
| `try!` | 0 | 3 (test setup) |
| `print()` | 0 (uses `os.Logger`) | 0 (CLI uses print correctly) |
| Empty catch blocks | 0 | 0 |
| TODO/FIXME/HACK | 0 | 0 |

This is excellent. The codebase consistently uses optional binding and proper error handling throughout.

## Dead / Unused Code

### Unused notification names

13 notification names are defined in `GhosttyApp.swift:528-556` but may not be observed in CalyxWindowController:

```
ghosttyCloseTab          ghosttyCloseWindow
ghosttyCellSizeChange    ghosttyInitialSize
ghosttySizeLimit         ghosttyConfigChange
ghosttyColorChange       ghosttyToggleFullscreen
ghosttyRendererHealth    ghosttyRingBell
ghosttyShowChildExited   ghosttyStartSearch
ghosttyEndSearch         ghosttySearchTotal
ghosttySearchSelected
```

Some of these are observed in `SurfaceView` or `SurfaceScrollView`, but several appear to be vestigial from Ghostty's original code. **Verify each with grep before deleting.**

### Redundant selectTab methods

9 individual `@objc` methods that all call `selectTabByIndex`:

```swift
// CalyxWindowController.swift:1343-1351
@objc func selectTab1(_ sender: Any?) { selectTabByIndex(0) }
@objc func selectTab2(_ sender: Any?) { selectTabByIndex(1) }
// ... through selectTab9
```

These exist for NSMenu target-action. Could be consolidated into a single tagged method.

### Dead binding

```swift
// CalyxWindowController.swift:1324
_ = group // silence warning
```

## Duplicated Logic

### Token generation (3 locations)

Same 32-byte `SecRandomCopyBytes` -> hex pattern:

| Location | File:Line |
|----------|-----------|
| IPC auto-start | `AppDelegate.swift:571-576` |
| IPC enable | `CalyxWindowController.swift:1758-1764` |
| Browser server | `BrowserServer.swift:79-82` |

**Extract to a shared `SecurityUtils.generateHexToken()` function.**

### Enter key event construction (2 locations)

Identical `ghostty_input_key_s` setup with keycode 0x24:

| Location | File:Line |
|----------|-----------|
| Compose overlay send | `CalyxWindowController.swift:901-931` |
| Review submission | `CalyxWindowController.swift:1869-1891` |

**Extract to a `sendEnterKey(to controller:, delay:)` helper.**

### Tab cleanup pattern (4 locations)

Same sequence repeated:

```swift
browserControllers.removeValue(forKey: tabID)
diffTasks[tabID]?.cancel()
diffTasks.removeValue(forKey: tabID)
diffStates.removeValue(forKey: tabID)
reviewStores.removeValue(forKey: tabID)
closingTabIDs.insert(tabID)
```

Found in: `closeTab`, `closeActiveGroup`, `closeAllTabsInGroup`, `windowWillClose`.

**Extract to `cleanupTabResources(id:)` method.**

## Large Files

| File | Lines | Concern |
|------|-------|---------|
| CalyxWindowController.swift | 1,965 | **CRITICAL** -- God object, needs decomposition |
| SurfaceView.swift | 881 | Large input handler (keyboard, mouse, IME) |
| AppDelegate.swift | 845 | Too many responsibilities (menu, persistence, IPC, testing) |
| GhosttyAction.swift | 797 | 40+ action case handlers in single router |
| DiffView.swift | 731 | NSView + NSTextView + ruler + comments |
| SidebarContentView.swift | 626 | SwiftUI view with multiple sub-views |
| GhosttyApp.swift | 557 | Singleton + C callbacks |
| SurfaceScrollView.swift | 543 | Scroll handling + search bar + throttling |
| CalyxMCPServer.swift | 520 | TCP server + JSON-RPC + routing |
| GitService.swift | 492 | Process spawning + async bridge |
| SettingsWindowController.swift | 456 | Settings UI + config management |

## Overly Complex Functions

### buildMainContentView() -- 57 lines of closure wiring

Not complex logic, but extremely verbose. All 22+ closures passed to MainContentView are wired here.

### performDebugSelect() -- 125 lines of UI testing support

Reads JSON from pasteboard, calculates cell positions, simulates mouse drags via ghostty FFI. This is test-only code but lives in production `AppDelegate`. Should be behind `#if DEBUG` or in a test support target.

## Test Coverage

**580+ test functions across 49 test files.**

| Area | Test File Lines | Functions |
|------|----------------|-----------|
| Browser Automation | 898 | 40+ |
| Diff/Review Store | 837 | 30+ |
| Session Model | 755 | 35+ |
| MCP Server | 614 | 25+ |
| Session Persistence | 592 | 20+ |
| Split Tree | 561 | 30+ |
| Codex Config | 520 | 20+ |
| MCP Protocol | 486 | 20+ |
| IPC Store | 479 | 20+ |
| Selection Handling | 423 | 15+ |
| Claude Config | 411 | 15+ |
| HTTP Parser | 320 | 15+ |
| + 37 more files | ... | ... |

**Coverage gaps**: Integration tests for focus management, theme rendering, and multi-window scenarios are likely limited.

## Classification

| Finding | Category |
|---------|----------|
| Unused notification names | Safe to delete (after grep verification) |
| `selectTab1-9` methods | Safe to refactor (one `@objc` with tag) |
| `_ = group` silencing | Safe to delete |
| Token generation duplication | Needs refactor (extract helper) |
| Enter key event duplication | Needs refactor (extract helper) |
| Tab cleanup pattern duplication | Needs refactor (extract method) |
| `performDebugSelect` in production | Needs refactor (move behind `#if DEBUG`) |
| CalyxWindowController size | Dangerous to touch without incremental plan |
| SurfaceView size | Dangerous to touch (deep AppKit/ghostty coupling) |
