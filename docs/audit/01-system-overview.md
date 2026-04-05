# Phase 1: System Overview

## What the Application Does

CTerm is a macOS 26+ native terminal emulator that wraps [libghostty](https://github.com/ghostty-org/ghostty) -- Ghostty's Metal-accelerated terminal rendering engine -- with a Liquid Glass UI shell. It is not just a terminal: it's a multi-modal workspace combining:

1. **Terminal tabs with split panes** -- Ghostty surfaces rendered via Metal, organized in a binary split tree
2. **Embedded browser tabs** -- WebKit-based tabs alongside terminals
3. **Git integration** -- Diff viewer, commit history, file staging sidebar
4. **AI agent IPC** -- MCP server enabling Claude Code / Codex CLI instances to communicate across panes
5. **Browser scripting** -- A local HTTP server (first available localhost port in `41840...41849`) for CLI-driven browser automation
6. **Code review overlay** -- Compose overlay and diff review comments that can be sent directly to AI agent terminals
7. **Session persistence** -- Atomic save/restore with crash-loop detection
8. **Quick Terminal** -- Visor-style dropdown terminal

**Tech stack**: Swift 6.2, AppKit + SwiftUI (bridged via `NSHostingView`), libghostty (Metal GPU rendering), XcodeGen for project generation.

## Core User Flows

### Launch to Terminal

```
AppDelegate.applicationDidFinishLaunching
  -> init GhosttyAppController.shared (ghostty_app_t singleton)
  -> createNewWindow()
  -> WindowSession + Tab
  -> CTermWindowController
  -> setupTerminalSurface()
  -> SurfaceRegistry.createSurface()
  -> GhosttySurface
  -> Metal rendering
```

### Tab/Split Operations

```
User input
  -> ghostty C callbacks
  -> NotificationCenter posts (.ghosttyNewSplit, .ghosttyCloseSurface, etc.)
  -> typed event wrappers in GhosttyNotificationEvents
  -> CTermWindowController notification handlers
  -> mutate SplitTree (value type)
  -> SplitContainerView.updateLayout()
```

### Session Restore

```
restoreSession()
  -> SessionPersistenceActor.restore()
  -> JSON decode
  -> recreate WindowSession hierarchy
  -> remap leaf UUIDs
  -> create new surfaces with old pwds
```

### Config Reload

```
~/.config/ghostty/config file change
  -> ConfigFileWatcher (FS events)
  -> ConfigReloadCoordinator (debounced)
  -> GhosttyConfigManager reload
  -> ghostty_app_update_config
  -> SurfaceRegistry.applyConfig to all windows
```

## Main Modules / Layers

| Layer | Role | Key Files |
|-------|------|-----------|
| **App** | Lifecycle, window management | `AppDelegate`, `main.swift` |
| **GhosttyBridge** | All ghostty C FFI, surface management, config, event translation | `GhosttyFFI`, `GhosttyApp`, `GhosttyConfig`, `SurfaceView`, `MetalView` |
| **Models** | Session hierarchy, split tree, surface registry | `AppSession`, `WindowSession`, `TabGroup`, `Tab`, `SplitTree`, `SurfaceRegistry` |
| **Views** | SwiftUI views + AppKit bridging | `MainContentView`, `CTermWindowController`, `SidebarContentView`, `TabBarContentView` |
| **Features** | Self-contained modules | Browser, IPC, Git, Search, CommandPalette, Persistence, QuickTerminal, Settings, etc. |
| **Input** | Keyboard handling | `ShortcutManager`, `GlobalEventTap` |
| **CTermCLI** | Bundled CLI tool | `cterm browser`, MCP client commands |

## Data Flow

### Ghostty events to UI

```
ghostty C callbacks
  -> Notification posts
    -> typed notification event wrappers
      -> CTermWindowController handlers
        -> Model mutation (Tab.splitTree, Tab.title, etc.)
        -> @Observable propagation -> SwiftUI re-render
        -> SessionPersistenceActor.save() (debounced)
```

### Session hierarchy

```
AppDelegate
  +-- GhosttyAppController.shared   (ghostty_app_t singleton, config, callbacks)
  +-- AppSession                    (all windows)
       +-- WindowSession            (tabs + groups for one NSWindow)
            +-- TabGroup            (colored group of tabs)
                 +-- Tab            (browser tab OR terminal tab)
                      +-- SplitTree (binary tree of panes)
                           +-- leaf UUID -> SurfaceRegistry -> GhosttySurface
```

## State Management Approach

### Observable models

`@Observable` classes (`AppSession`, `WindowSession`, `TabGroup`, `Tab`, `WindowViewState`, `GitState`, `BrowserState`, `DiffReviewStore`, `ClaudeUsageMonitor`) -- all `@MainActor`, using Swift 5.9+ Observation framework.

### Immutable value types

`SplitTree` is a `Codable`, `Equatable`, `Sendable` struct with an `indirect enum SplitNode`. Mutations produce new tree values -- no in-place mutation.

### Surface registry

`SurfaceRegistry` is a mutable dictionary `[UUID: RegistryEntry]` with `@MainActor` isolation. Each entry tracks a `SurfaceView`, `GhosttySurfaceController`, lifecycle state, and drag state.

### View bridge

`WindowViewState` is an `@Observable` bridge owned by `CTermWindowController`, passed once to `MainContentView` at setup. The controller calls `updateViewState()` whenever the active tab changes, making SwiftUI updates automatic without rebuilding the view tree.

### Event bus

`NotificationCenter` is the primary inter-layer communication mechanism. 28 notification names are defined, all posted from ghostty C callbacks through `GhosttyApp.swift`, with payloads decoded in `GhosttyNotificationEvents.swift` rather than ad hoc in controllers.

### Singletons

10 singletons manage global state:

| Singleton | Purpose |
|-----------|---------|
| `GhosttyAppController.shared` | ghostty_app_t lifecycle, config |
| `CTermMCPServer.shared` | IPC server |
| `BrowserServer.shared` | Browser automation server |
| `SessionPersistenceActor.shared` | Session save/restore |
| `SettingsWindowController.shared` | Settings window |
| `SecureInput.shared` | Secure keyboard entry |
| `NotificationManager.shared` | Desktop notifications |
| `GlobalEventTap.shared` | System-wide keybinds |
| `GhosttyThemeProvider.shared` | Theme color tracking |
| `ClaudeUsageMonitor.shared` | Claude usage stats |
