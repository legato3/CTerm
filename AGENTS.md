# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working in this repository.

## Audit

The repo has a full audit in `docs/audit/`. Read it before major changes. Start with:
- `docs/audit/02-architecture.md` — current architecture, extracted controllers, remaining coupling
- `docs/audit/07-fragility-map.md` — areas that still break easily
- `docs/audit/10-refactor-plan.md` — incremental decomposition plan
- `docs/audit/11-future-risk.md` — current risk posture after recent refactors
- `docs/CONCURRENCY.md` — why the existing `nonisolated(unsafe)` uses exist

## What This Is

CTerm is a macOS 26+ native terminal application built on [libghostty](https://github.com/ghostty-org/ghostty). It wraps Ghostty's Metal terminal engine in a native Liquid Glass shell and adds tabs, groups, split panes, embedded browser tabs, git tooling, AI agent IPC, browser scripting, quick terminal, and session persistence.

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
  └── GhosttyAppController.shared   (ghostty_app_t singleton, config, callbacks)
  └── AppSession                    (all windows)
       └── WindowSession            (tabs + groups for one NSWindow)
            └── TabGroup            (colored group of tabs)
                 └── Tab            (terminal, browser, diff, etc.)
                      └── SplitTree (binary tree of panes)
                           └── leaf UUID → SurfaceRegistry → GhosttySurface
```

### Key conventions

- **`@MainActor` is the default** — UI, session, controller, and view-state code stay on the main actor.
- **All ghostty C API calls go through `GhosttyFFI`** in `CTerm/GhosttyBridge/GhosttyFFI.swift`. Keep it a thin wrapper layer.
- **NotificationCenter is still the event bus**, but notification payload decoding should go through the typed wrappers in `CTerm/GhosttyBridge/GhosttyNotificationEvents.swift`. Do not add new raw `userInfo` parsing in controllers.
- **`WindowActions` replaces the old closure explosion** — view-to-controller actions are injected through the SwiftUI environment from `CTermWindowController`.
- **No force unwraps, force casts, or `try!` in production code.**
- **`nonisolated(unsafe)` is allowed only for justified interop or write-once/read-only state.** Match the existing documented patterns in `docs/CONCURRENCY.md`.

### Known architectural issues

- **`CTermWindowController` is still too large** — about 1,900 lines even after extracting `GitController`, `ReviewController`, `FocusManager`, `BrowserManager`, `ComposeOverlayController`, `SplitController`, `IPCWindowController`, and `TabLifecycleController`. Avoid adding new responsibilities there.
- **Session and tab lifecycle logic is still distributed** across `AppDelegate`, `CTermWindowController`, and feature controllers. Be careful when changing restore, close, or cleanup behavior.
- **Singleton-heavy design remains** — `GhosttyAppController.shared`, `CTermMCPServer.shared`, `BrowserServer.shared`, `SessionPersistenceActor.shared`, and others still own global state.

### Directory structure

- `CTerm/App/` — app lifecycle (`AppDelegate`, `main.swift`)
- `CTerm/GhosttyBridge/` — Ghostty integration, config reload, surfaces, event translation, typed notification wrappers
- `CTerm/Models/` — session hierarchy, tabs, groups, split tree, surface registry
- `CTerm/Views/MainWindow/` — `CTermWindowController`, `MainContentView`, `WindowActions`, split and main-window glue
- `CTerm/Views/` — SwiftUI views for sidebar, tab bar, browser, git, glass, split UI
- `CTerm/Features/` — feature modules such as Browser, IPC, Git, Persistence, Search, ComposeOverlay, QuickTerminal, Notifications, Settings, TerminalSearch, TestRunner, TriggerEngine, Usage
- `CTerm/Input/` — global event tap and shortcut handling
- `CTerm/Helpers/` — utility code
- `CTermCLI/` — bundled `cterm` CLI built with `swift-argument-parser`
- `CTermTests/` — unit tests
- `CTermUITests/` — UI tests (`--uitesting` launch arg)

### Split pane model

`SplitTree` is an immutable value-type binary tree (`SplitNode.leaf(id:)` or `.split(SplitData)`). Each leaf UUID maps to a surface through `SurfaceRegistry`. Mutations replace tree values rather than editing nodes in place.

### Ghostty config

`GhosttyConfigManager` reads `~/.config/ghostty/config`, applies CTerm-managed overrides, and reloads through `ConfigReloadCoordinator`. Config changes propagate back into ghostty and surface state without rebuilding the app model.

### IPC / MCP server

`CTermMCPServer` exposes a localhost MCP server on ports `41830...41839` for Claude Code and Codex peers running in terminal panes. `IPCConfigManager` coordinates config writes to `~/.claude.json` and `~/.codex/config.toml`. Message brokering lives behind the `IPCStore` actor.

### Browser scripting

`BrowserServer` exposes localhost browser automation on ports `41840...41849`. `BrowserTabBroker` and `BrowserToolHandler` route commands to `WKWebView`-backed browser tabs. The bundled CLI entry point is `cterm browser` in `CTermCLI/BrowserCommands.swift`.

## Project configuration

`project.yml` is the source of truth for targets, dependencies, schemes, and build settings. Main targets:
- **CTerm** — app target, depends on `GhosttyKit.xcframework`, system frameworks, and `CTermCLI`
- **CTermCLI** — `cterm` command-line tool, depends on `swift-argument-parser`
- **CTermTests** / **CTermUITests** — test bundles

`CTerm-Bridging-Header.h` bridges GhosttyKit C headers into Swift.

## Session persistence

`SessionPersistenceActor` saves and restores `~/.cterm/sessions.json` using atomic temp-and-rename writes, backup rotation, and crash-loop detection. Persistence is debounced through `requestSave()`. Diff tabs are intentionally excluded from saved sessions.
