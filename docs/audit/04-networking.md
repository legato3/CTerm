# Phase 4: Networking & Failure Handling

## Network Layer Structure

Three independent localhost-only services:

| Server | Port Range | Auth | Protocol | Purpose |
|--------|-----------|------|----------|---------|
| `CTermMCPServer` | 41830-41839 | Bearer token | HTTP/1.1 + JSON-RPC | AI agent IPC |
| `BrowserServer` | 41840-41849 | Bearer token | HTTP/1.1 + JSON | Browser automation CLI |
| CLI (`cterm` tool) | Client only | Bearer token | curl subprocess | CLI commands |

All use a hand-rolled `HTTPParser` (211 lines) instead of URLSession.

## CTermMCPServer

### Architecture
- `@MainActor` singleton using `Network.framework` (`NWListener`, `NWConnection`)
- Implements MCP 2024-11-05 protocol with JSON-RPC 2.0
- 8 tools: `register_peer`, `list_peers`, `send_message`, `broadcast`, `receive_messages`, `ack_messages`, `get_peer_status`, `heartbeat`
- Backed by `IPCStore` actor for thread-safe message brokering

### Error Handling
- HTTP parse errors mapped to status codes (413, 400, 408, 500)
- JSON-RPC error codes: `-32700` (parse error), `-32601` (method not found)
- Auth failure returns 401 with no body
- Tool errors return `{content: [{type: "text", text: error_message}], isError: true}`

### TTL Policies
- Peer TTL: 10 minutes
- Message TTL: 5 minutes
- Max messages per peer: 100
- Max content size: 64KB
- Lazy expiration (purged on read, not proactively)

## BrowserServer

### Architecture
- `@MainActor` singleton, auto-starts on app launch
- 24 browser automation commands dispatched to `BrowserToolHandler`
- JavaScript-based DOM interaction via `WKWebView.evaluateJavaScript()`

### Error Handling
- 404: Not POST /browser
- 401: Invalid/missing token
- 400: No body or parse error
- 200 with `{ok: false, error: "..."}`: Tool-level errors

## HTTPParser (Hand-Rolled)

### Size Limits
- Headers: 8KB max
- Body: 1MB max

### Error Types
- `headerTooLarge`, `bodyTooLarge`, `invalidContentLength`, `malformedRequest`, `timeout` (unused)

### Concerns
- **No HTTP/2 support**: Only HTTP/1.1
- **No chunked encoding**: Requires Content-Length
- **Header injection risk**: No validation of header values (could contain `\r\n`)
- **No keep-alive**: Each connection closed after response

## GitService

### Architecture
Uses `Process` (NSTask) to run git commands with manual timeout handling:

```swift
DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: timeoutItem)
```

Combined with `DispatchSemaphore` and `withCheckedThrowingContinuation` to bridge back to async/await.

### Concerns
- Mixing GCD semaphores with structured concurrency is an anti-pattern
- 10-second hard timeout for all git operations
- No retry logic

## CLI (cterm tool)

### Architecture
- Uses `swift-argument-parser` for 24 browser subcommands
- Reads connection info from `~/.config/cterm/browser.json`
- Invokes `/usr/bin/curl` as subprocess for HTTP requests

### Timeouts
- `--connect-timeout 5` (connection)
- `--max-time 30` (total)

### Security Concern
Bearer token passed as curl argument -- visible in `ps` output on shared systems.

## Fragile Points

### 1. BrowserServer.generateToken() ignores SecRandomCopyBytes return

```swift
// BrowserServer.swift:81
_ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
```

If this fails, `bytes` remains all-zeros -- a predictable "token". The MCP server version correctly checks the return value; the browser server does not.

### 2. GitService semaphore+GCD pattern

Concurrent pipe reading with `DispatchGroup`, semaphore waiting, then `withCheckedThrowingContinuation` -- three concurrency mechanisms in one function. Fragile and hard to maintain.

### 3. No server-side timeout enforcement

The HTTP parser defines a `timeout` error case but never throws it. Slow clients can hold connections indefinitely.

## Silent Failures

| Location | What's swallowed |
|----------|-----------------|
| `CTermWindowController:1611` | `loadMoreCommits` errors |
| `CTermWindowController:1636` | `expandCommit` errors |
| `BrowserServer.start()` | Port binding failures (loops through 10 ports silently) |

## Recommended Improvements

1. **Fix `BrowserServer.generateToken()`** -- check `SecRandomCopyBytes` return value, log/fail on error
2. **Replace `GitService.runGit()` semaphore pattern** -- use `Process` with async/await or `AsyncStream`
3. **Add retry with user-visible feedback** for `loadMoreCommits` -- at minimum log a warning
4. **Add request logging** to both servers for debugging and auditing
5. **Implement rate limiting** -- both servers accept unlimited concurrent connections
6. **Pass bearer token via stdin** instead of curl argument to avoid `ps` visibility
