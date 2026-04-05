# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Audit

A full codebase audit lives in `docs/audit/`. Read it before major changes. Key docs:
- `docs/audit/02-architecture.md` — structural risks, the CTermWindowController god class problem
- `docs/audit/07-fragility-map.md` — what breaks easily and why
- `docs/audit/10-refactor-plan.md` — incremental decomposition plan

## What This Is

CTerm is a macOS 26+ native terminal application built on [libghostty](https://github.com/ghostty-org/ghostty). It wraps the Ghostty terminal engine (via xcframework) with a native Liquid Glass UI, adding tabs, splits, sidebar, browser tabs, IPC, and other features on top.

**Tech stack**: Swift 6.2, AppKit + SwiftUI (bridged via `NSHostingView`), libghostty (Metal GPU rendering), XcodeGen for project generation.

## Build Commands

### First-time setup (building libghostty)

```bash
cd ghostty
SSL_CERT_FILE=/etc/ssl/cert.pem zig build -Demit-xcframework=true -Dxcframework-target=native
cd ..
cp -R ghostty/macos/GhosttyKit.xcframework .
```

`SSL_CERT_FILE` is required — without it Zig's HTTP client fails with `TlsInitializationFailed` on macOS.

If you get `cannot execute tool 'metal' due to missing Metal Toolchain`, run:
```bash
xcodebuild -downloadComponent MetalToolchain
```

The `ghostty/` directory is a git submodule. Zig version must match what's in `ghostty/build.zig.zon`.

### Generate Xcode project

```bash
xcodegen generate
```

Must re-run whenever `project.yml` changes. `CTerm.xcodeproj` is generated and not committed.

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

```
AppDelegate
  └── GhosttyAppController.shared   (ghostty_app_t singleton, config, callbacks)
  └── AppSession                    (all windows)
       └── WindowSession            (tabs + groups for one NSWindow)
            └── TabGroup            (colored group of tabs)
                 └── Tab            (browser tab OR terminal tab)
                      └── SplitTree (binary tree of panes)
                           └── leaf UUID → SurfaceRegistry → GhosttySurface
```

### Key conventions

- **`@MainActor` everywhere** — all UI and model code is `@MainActor`. Never dispatch UI work off the main actor.
- **All ghostty C API calls go through `GhosttyFFI`** (`CTerm/GhosttyBridge/GhosttyFFI.swift`). This is a thin enum of static wrapper methods — no business logic there.
- **NotificationCenter remains the event bus** — notification payload decoding should go through the typed wrappers in `CTerm/GhosttyBridge/GhosttyNotificationEvents.swift`. Do not add new raw `userInfo` parsing in controllers.
- **`WindowActions` replaces the old closure explosion** — view-to-controller actions are injected through the SwiftUI environment from `CTermWindowController`.
- **`GhosttyAppController.shared`** is the singleton that owns `ghostty_app_t`, manages config reload, and handles C callbacks from libghostty.
- **No force unwraps, force casts, or `try!` in production code.** Keep it that way.
- **`nonisolated(unsafe)`** is used for documented C interop and read-only-after-init patterns. Follow `docs/CONCURRENCY.md` before adding new ones.

### Known architectural issues

- **`CTermWindowController` is still too large** — despite the extracted controllers (`GitController`, `ReviewController`, `FocusManager`, `BrowserManager`, `ComposeOverlayController`, `SplitController`, `IPCWindowController`, `TabLifecycleController`), it still concentrates too much responsibility. Avoid adding new concerns there.
- **Session and tab lifecycle logic is still distributed** across `AppDelegate`, `CTermWindowController`, and feature controllers. Be careful when changing restore, close, or cleanup behavior.
- **Singleton-heavy design remains** — `GhosttyAppController.shared`, `CTermMCPServer.shared`, `BrowserServer.shared`, `SessionPersistenceActor.shared`, and others still own global state.

### Directory structure

- `CTerm/App/` — `AppDelegate`, `main.swift`
- `CTerm/GhosttyBridge/` — all ghostty integration: `GhosttyFFI`, `GhosttyApp`, `GhosttyConfig`, `GhosttySurface`, `SurfaceView`, `MetalView`, config watcher/reloader, event translation
- `CTerm/Models/` — data model: `AppSession`, `WindowSession`, `TabGroup`, `Tab`, `SplitTree`, `SurfaceRegistry`, `ThemeColor`
- `CTerm/Views/` — SwiftUI views organized by area: `MainWindow/`, `Sidebar/`, `TabBar/`, `Split/`, `Browser/`, `Git/`, `Glass/`
- `CTerm/Features/` — self-contained feature modules: `Browser/`, `CommandPalette/`, `ComposeOverlay/`, `Git/`, `IPC/`, `Notifications/`, `Persistence/`, `QuickTerminal/`, `Search/`, `SecureInput/`, `Settings/`, `TerminalSearch/`, `TestRunner/`, `TriggerEngine/`, `Usage/`
- `CTerm/Input/` — global event tap, shortcut manager
- `CTerm/Helpers/` — utilities
- `CTermCLI/` — the `cterm` CLI tool (bundled into app; uses `swift-argument-parser`)
- `CTermTests/` — unit tests
- `CTermUITests/` — UI tests (pass `--uitesting` launch arg)

### Split pane model

`SplitTree` is an immutable value-type binary tree (`SplitNode` enum: `.leaf(id: UUID)` or `.split(SplitData)`). Each leaf UUID maps to a `GhosttySurface` via `SurfaceRegistry`. Mutations produce new tree values — no in-place mutation.

### Ghostty config

`GhosttyConfigManager` reads `~/.config/ghostty/config` and applies overrides for CTerm-managed keys (background opacity, blur, etc.). The file watcher triggers debounced reloads via `ConfigReloadCoordinator`. Config changes propagate via `ghostty_app_reload_config`.

### IPC / MCP server

`CTermMCPServer` implements a local MCP server (port 41830-41839) enabling Claude Code and Codex CLI instances in different terminal panes to communicate. `IPCConfigManager` writes the MCP config to `~/.claude.json` and `~/.codex/config.toml`. Backed by `IPCStore` actor with TTL-based peer/message expiration. See `docs/audit/04-networking.md`.

### Browser scripting

`BrowserServer` binds to the first available localhost port in `41840...41849`. `BrowserTabBroker` coordinates between `BrowserTabController` instances and the CLI. The `cterm browser` subcommand (in `CTermCLI/BrowserCommands.swift`) communicates with this server. Both servers use a hand-rolled `HTTPParser` and bearer token auth. See `docs/audit/04-networking.md`.

## Project configuration

`project.yml` (XcodeGen spec) is the source of truth for targets, dependencies, and build settings. Targets:
- **CTerm** — main app, depends on `GhosttyKit.xcframework`, system frameworks, and `CTermCLI`
- **CTermCLI** — `cterm` command-line tool, depends on `swift-argument-parser`
- **CTermTests** / **CTermUITests** — test bundles

The `CTerm-Bridging-Header.h` (listed as a `fileGroup`) bridges GhosttyKit C headers into Swift.

## Session persistence

`SessionPersistenceActor` (Swift actor) saves/restores to `~/.cterm/sessions.json` with atomic temp+rename writes, backup rotation, and crash-loop detection (max 3 recovery attempts). Debounced saves trigger on every meaningful state change via `requestSave()`. Diff tabs are excluded from persistence by design.
