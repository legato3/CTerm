# AGENTS.md

This file provides guidance to Codex when working in this repository.

## Audit

The repo has a full audit in `docs/audit/`. Read it before structural changes. Start with:
- `docs/audit/02-architecture.md` — current architecture, extracted controllers, remaining coupling
- `docs/audit/07-fragility-map.md` — areas that still break easily
- `docs/audit/10-refactor-plan.md` — incremental decomposition plan
- `docs/audit/11-future-risk.md` — risk posture after the recent refactors
- `docs/CONCURRENCY.md` — why the existing `nonisolated(unsafe)` uses exist

The audit is directionally correct, but some exact counts and file sizes can lag `HEAD`. Trust the architectural guidance over any stale numeric callout.

## What This Is

CTerm is a macOS 26+ native terminal application built on [libghostty](https://github.com/ghostty-org/ghostty). It wraps Ghostty's Metal terminal engine in a native Liquid Glass shell and adds tab groups, split panes, embedded browser tabs, git review tooling, AI agent IPC, browser scripting, command palette, quick terminal, approval flows, and session persistence.

**Tech stack**: Swift 6.2, AppKit + SwiftUI bridged via `NSHostingView`, libghostty via `GhosttyKit.xcframework`, XcodeGen for project generation.

## Build Commands

### First-time setup (building libghostty)

```bash
cd ghostty
SSL_CERT_FILE=/etc/ssl/cert.pem zig build -Demit-xcframework=true -Dxcframework-target=native
cd ..
cp -R ghostty/macos/GhosttyKit.xcframework .
```

`SSL_CERT_FILE` is required on macOS or Zig can fail with `TlsInitializationFailed`.

If you get `cannot execute tool 'metal' due to missing Metal Toolchain`, run:

```bash
xcodebuild -downloadComponent MetalToolchain
```

The `ghostty/` directory is a git submodule. Zig must match the version pinned in `ghostty/build.zig.zon`.

### Generate Xcode project

```bash
xcodegen generate
```

Re-run this whenever `project.yml` changes. `CTerm.xcodeproj` is generated and not committed.

### Build

```bash
xcodebuild -project CTerm.xcodeproj -scheme CTerm -configuration Debug build
```

### Run tests

```bash
# All unit tests
xcodebuild -project CTerm.xcodeproj -scheme CTermTests -configuration Debug test

# Single test class
xcodebuild -project CTerm.xcodeproj -scheme CTermTests -configuration Debug test -only-testing:CTermTests/SplitTreeTests

# UI tests
xcodebuild -project CTerm.xcodeproj -scheme CTermUITests -configuration Debug test
```

## Architecture

### Layer overview

```text
AppDelegate
  ├── GhosttyAppController.shared   (ghostty_app_t singleton, config, callbacks)
  ├── AppSession                    (all managed windows)
  │    └── WindowSession            (groups + sidebar/window state for one NSWindow)
  │         └── TabGroup            (colored group of tabs)
  │              └── Tab            (.terminal / .browser / .diff)
  │                   └── SplitTree (immutable binary tree of panes)
  │                        └── leaf UUID → SurfaceRegistry → GhosttySurface / SurfaceView
  └── BrowserTabBroker              (routes browser automation into WKWebView tabs)
```

### Key conventions

- `@MainActor` is the default for UI, session, controller, and view-state code.
- `@Observable` is used heavily for shared UI/session state. Prefer extending existing observable models instead of adding new ad hoc callback chains.
- All ghostty C API calls go through `CTerm/GhosttyBridge/GhosttyFFI.swift`. Keep it a thin wrapper layer.
- NotificationCenter is still the event bus, but ghostty payload decoding should go through typed wrappers in `CTerm/GhosttyBridge/GhosttyNotificationEvents.swift`. Do not add new raw `userInfo` parsing in controllers.
- `WindowActions` replaces the old closure explosion. View-to-controller actions are injected through the SwiftUI environment from `CTermWindowController`.
- `SplitTree` is an immutable value type. Replace tree values instead of mutating nodes in place.
- No force unwraps, force casts, or `try!` in production code.
- `nonisolated(unsafe)` is allowed only for justified interop or write-once/read-only state. Match the documented patterns in `docs/CONCURRENCY.md`.
- Prefer extending extracted feature controllers/managers before adding more responsibility to `CTermWindowController`.

### Known architectural issues

- `CTermWindowController` is still too large. It is over 2,000 lines at current `HEAD` even after extracting `GitController`, `ReviewController`, `FocusManager`, `BrowserManager`, `ComposeOverlayController`, `SplitController`, `IPCWindowController`, and `TabLifecycleController`. Avoid adding new responsibilities there.
- Session and tab lifecycle logic is still distributed across `AppDelegate`, `CTermWindowController`, `TabLifecycleController`, `QuickTerminalController`, and persistence code. Be careful when changing restore, close, or cleanup behavior.
- Singleton-heavy design remains. `GhosttyAppController.shared`, `CTermMCPServer.shared`, `BrowserServer.shared`, `SessionPersistenceActor.shared`, `SettingsWindowController.shared`, and other singletons still own global state.
- NotificationCenter is still a key integration boundary. If you add a new ghostty notification, add or update the typed event wrapper in the same change.

### Directory structure

- `CTerm/App/` — app lifecycle (`AppDelegate`, `main.swift`)
- `CTerm/GhosttyBridge/` — Ghostty integration, config reload, surfaces, event translation, typed notification wrappers
- `CTerm/Models/Session/` — session hierarchy and tab state (`AppSession`, `WindowSession`, `TabGroup`, `Tab`)
- `CTerm/Models/` — shared model types such as `SplitTree`, `SurfaceRegistry`, `WindowViewState`
- `CTerm/Views/MainWindow/` — `CTermWindowController`, `MainContentView`, `WindowActions`, and main-window glue
- `CTerm/Views/Split/` — split container and pane layout views
- `CTerm/Views/Sidebar/`, `CTerm/Views/TabBar/`, `CTerm/Views/Browser/`, `CTerm/Views/Git/`, `CTerm/Views/Approval/`, `CTerm/Views/Agent*` — SwiftUI UI layers
- `CTerm/Features/` — feature modules such as Browser, IPC, Git, Persistence, QuickTerminal, Settings, TerminalSearch, TestRunner, TaskQueue, ComposeOverlay, AgentSession, AgentPermissions, AgentLoop, ActiveAI, Notifications, Usage
- `CTerm/Input/` — global event tap and shortcut handling
- `CTerm/Helpers/` — utility code
- `CTermCLI/` — bundled `cterm` CLI built with `swift-argument-parser`
- `CTermTests/` — unit tests
- `CTermUITests/` — UI tests (`--uitesting` launch arg)

### Split pane model

`SplitTree` is an immutable value-type binary tree (`SplitNode.leaf(id:)` or `.split(SplitData)`). Each leaf UUID maps to a surface through `SurfaceRegistry`. Mutations replace tree values rather than editing nodes in place.

### Ghostty config

`GhosttyConfigManager` in `CTerm/GhosttyBridge/GhosttyConfig.swift` loads the user's Ghostty config, then layers CTerm-managed overrides from `~/.config/cterm/`:
- `cterm-glass.conf`
- `cterm-user-settings.conf`
- `cterm-runtime.conf`

Config changes propagate back into ghostty and surface state without rebuilding the app model.

### IPC / MCP server

`CTermMCPServer` exposes a localhost MCP server on ports `41830...41839` with bearer-token auth for Claude Code and Codex peers running in terminal panes.

`IPCConfigManager` coordinates config writes to Claude Code and Codex through:
- `CTerm/Features/IPC/ClaudeConfigManager.swift`
- `CTerm/Features/IPC/CodexConfigManager.swift`

Message brokering and project state live behind the `IPCStore` actor.

### Browser scripting

`BrowserServer` auto-starts on app launch, exposes localhost browser automation on ports `41840...41849`, and writes connection state to `~/.config/cterm/browser.json`.

`BrowserTabBroker` and `BrowserToolHandler` route commands to `WKWebView`-backed browser tabs. The bundled CLI entry point is `cterm browser` in `CTermCLI/BrowserCommands.swift`.

## Project configuration

`project.yml` is the source of truth for targets, dependencies, schemes, and build settings. Main targets:
- `CTerm` — app target, depends on `GhosttyKit.xcframework`, system frameworks, and `CTermCLI`
- `CTermCLI` — `cterm` command-line tool, depends on `swift-argument-parser`
- `CTermTests` / `CTermUITests` — test bundles

`CTerm-Bridging-Header.h` bridges GhosttyKit C headers into Swift.

## Session persistence

`SessionPersistenceActor` saves and restores `~/.cterm/sessions.json` using atomic temp-and-rename writes, backup rotation, and crash-loop detection. It also migrates the legacy Application Support session file on first restore if needed.

Persistence is debounced through `save(_:)`, with `saveImmediatelySync(_:)` reserved for shutdown. UI tests can override the storage directory with `CTERM_UITEST_SESSION_DIR`. Diff tabs are intentionally excluded from saved sessions.
