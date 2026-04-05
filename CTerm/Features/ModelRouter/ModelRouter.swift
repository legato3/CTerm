// ModelRouter.swift
// CTerm
//
// Picks an AgentBackend per step role based on the active routing preset.
// Scope: multi-step sessions only. Inline/compose paths keep user-explicit
// backend selection. Peer-delegated sessions skip the router (backend
// already fixed to `.peer(name:)`).
//
// Hard-override: if the session's active profile declares a
// `preferredBackend`, that wins over any preset assignment.
//
// Health-check: when the preset picks Ollama, the router consults a
// cached flag set by a non-blocking async probe (TTL 30s). If Ollama is
// unhealthy, routing falls back to the provided fallback backend.

import Foundation
import Observation
import OSLog

private let logger = Logger(subsystem: "com.legato3.cterm", category: "ModelRouter")

@Observable
@MainActor
final class ModelRouter {

    static let shared = ModelRouter()

    private static let activePresetIDDefaultsKey = "CTerm.ModelRouter.ActivePresetID"

    var activePresetID: String {
        didSet {
            guard oldValue != activePresetID else { return }
            UserDefaults.standard.set(activePresetID, forKey: Self.activePresetIDDefaultsKey)
        }
    }

    /// Cached Ollama health flag. Default true so first pick doesn't fall
    /// back before any probe has run.
    private var ollamaHealthy: Bool = true
    private var lastHealthCheck: Date = .distantPast
    private let healthCheckTTL: TimeInterval = 30

    /// All known presets. Built-ins only in v1 — custom presets are a
    /// future enhancement.
    let presets: [ModelRoutingPreset] = ModelRoutingPreset.builtIn

    // MARK: - Init

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Self.activePresetIDDefaultsKey),
           ModelRoutingPreset.builtIn.contains(where: { $0.id == raw }) {
            self.activePresetID = raw
        } else {
            self.activePresetID = ModelRoutingPreset.localFirst.id
        }
    }

    #if DEBUG
    /// Test-only initializer. Bypasses UserDefaults and singleton.
    init(presetID: String) {
        if ModelRoutingPreset.builtIn.contains(where: { $0.id == presetID }) {
            self.activePresetID = presetID
        } else {
            self.activePresetID = ModelRoutingPreset.localFirst.id
        }
    }
    #endif

    // MARK: - Lookup

    var activePreset: ModelRoutingPreset {
        presets.first(where: { $0.id == activePresetID }) ?? ModelRoutingPreset.localFirst
    }

    func preset(id: String) -> ModelRoutingPreset? {
        presets.first(where: { $0.id == id })
    }

    // MARK: - Pick

    /// Resolve the backend for a given step role.
    /// - Parameters:
    ///   - role: The role of the step being routed.
    ///   - profileBackend: Optional hard-override from the session's profile.
    ///     When non-nil, it wins over preset + health-check.
    ///   - fallback: Backend to use when Ollama is unhealthy (default `.ollama`).
    func pick(
        role: StepRole,
        profileBackend: AgentBackend? = nil,
        fallback: AgentBackend = .ollama
    ) -> AgentBackend {
        // 1. Profile hard-override wins.
        if let profileBackend { return profileBackend }
        // 2. Look up active preset → SimpleBackend for role.
        let preset = activePreset
        guard let simple = preset.assignments[role] else { return fallback }
        let candidate = simple.agentBackend
        // 3. Health-check fallback (only for Ollama).
        return candidateWithHealthCheck(candidate, fallback: fallback)
    }

    // MARK: - Health check

    #if DEBUG
    /// Test-only: set the cached health flag directly so tests don't
    /// need network I/O.
    func _setOllamaHealthy(_ healthy: Bool) {
        self.ollamaHealthy = healthy
        self.lastHealthCheck = Date()
    }
    #endif

    private func candidateWithHealthCheck(_ candidate: AgentBackend, fallback: AgentBackend) -> AgentBackend {
        guard case .ollama = candidate else { return candidate }
        // If cache is stale, fire a probe. Non-blocking — just updates the
        // flag for the next call.
        if Date().timeIntervalSince(lastHealthCheck) > healthCheckTTL {
            lastHealthCheck = Date()
            Task { [weak self] in
                let healthy = await Self.probeOllama()
                await MainActor.run {
                    self?.ollamaHealthy = healthy
                }
            }
        }
        return ollamaHealthy ? candidate : fallback
    }

    private static func probeOllama() async -> Bool {
        let endpoint = OllamaCommandService.currentEndpoint()
        guard var url = URL(string: endpoint) else { return false }
        url.append(path: "api/tags")
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 3
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                return true
            }
            return false
        } catch {
            logger.debug("ModelRouter: Ollama health probe failed: \(error.localizedDescription)")
            return false
        }
    }
}
