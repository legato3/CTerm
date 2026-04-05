# Concurrency Notes

This document explains the ~25 `nonisolated(unsafe)` instances in the CTerm codebase.
They are intentional escape hatches from Swift's strict concurrency checking, not bugs.
Do not add new ones without justification.

## Category 1: C interop pointers (write-once, read-only after init)

These hold raw C pointers from libghostty. They are set once during initialization
and then only read. Swift's concurrency system can't verify this, so `nonisolated(unsafe)`
is used to suppress the warning.

| File | Property | Notes |
|------|----------|-------|
| `GhosttyApp.swift` | `app: ghostty_app_t?` | Set in `start()`, read-only thereafter |
| `GhosttyConfig.swift` | `config: ghostty_config_t?` | Rebuilt on config reload, protected by @MainActor call sites |
| `GhosttySurface.swift` | `surface: ghostty_surface_t?` | Set in `createSurface`, nil'd in `destroySurface` |

## Category 2: C callback captures (locals in nonisolated C callbacks)

libghostty calls back on arbitrary threads using C function pointers. Swift closures
can't be used directly; instead, raw function pointers capture context via `UnsafeRawPointer`.
The `let safe* = *` pattern extracts a local copy of each pointer so the closure body
can treat it as a non-isolated value.

| File | Pattern | Context |
|------|---------|---------|
| `GhosttyApp.swift` (×6) | `nonisolated(unsafe) let safeApp = app` | C wakeup/input/close callbacks |

These locals have scope limited to a single C callback invocation and are safe because:
- The underlying object outlives the callback (owned by GhosttyAppController.shared)
- The callback dispatches to `@MainActor` before touching Swift state

## Category 3: Static caches (read-only after init, used off main actor)

These static properties are computed lazily or assigned once at startup. All call
sites after initialization are reads, which are safe to perform from any thread.

| File | Property | Notes |
|------|----------|-------|
| `ClaudeUsageMonitor.swift` | `claudeDir`, `projectsDir`, `statsCachePath` | Path strings, written once |
| `ClaudeUsageMonitor.swift` | `iso8601`, `dayFormatter` | DateFormatter/ISO8601DateFormatter instances — not Sendable, but read-only after lazy init |

The monitor's `computeSync()` runs in a detached Task (off main actor). The formatters
must be accessible from that context.

## Category 4: Notification observer tokens

`NotificationCenter.addObserver(forName:...)` returns an opaque `Any` token that must
be stored to allow later removal. AppKit delivers these notifications on the main thread
but the token is stored on a class that may not be `@MainActor`.

| File | Property | Notes |
|------|----------|-------|
| `GhosttyThemeProvider.swift` | `observer: Any?` | NSNotification observer token |
| `SecureInput.swift` | `observers: [Any]` | Array of notification tokens |

## Category 5: Shared singletons and thread-safe init

| File | Property | Notes |
|------|----------|-------|
| `GlobalEventTap.swift` | `static let shared` | Singleton created before concurrency domain is established |
| `GlobalEventTap.swift` | `ghosttyApp: ghostty_app_t?` | Written in `install()`, read in CGEvent tap callback on system thread |

`GlobalEventTap` installs a `CGEventTap` whose callback runs on a dedicated system
thread. The `ghosttyApp` reference is written once before the tap is installed (before
any concurrent reads are possible).

## Category 6: AppKit view state accessed off main actor

| File | Property | Notes |
|------|----------|-------|
| `SurfaceView.swift` | `_hasSecureInput: Bool` | Updated from `SecureInput` notification path |
| `QuickTerminalController.swift` | `hiddenDock: HiddenDock?` | Written once in init, AppKit lifecycle |

## When to add a new nonisolated(unsafe)

Only add `nonisolated(unsafe)` when **all** of these apply:
1. The value is written once (or under a lock) and then only read
2. You've verified no data race exists through code inspection
3. There is no better alternative (actor isolation, `Sendable` wrapper, `@MainActor`)
4. You add a comment explaining why it's safe

If you're adding one to work around a Swift 6 error without understanding why, **stop and ask**.
