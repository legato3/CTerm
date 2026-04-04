import Foundation

enum ComposeAssistantMode: String, CaseIterable, Identifiable, Sendable {
    case shell
    case ollamaCommand

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .shell: return "Shell"
        case .ollamaCommand: return "Ollama"
        }
    }

    var placeholderText: String {
        switch self {
        case .shell:
            return "Type a shell command..."
        case .ollamaCommand:
            return "Describe what you want to do..."
        }
    }
}

enum ComposeAssistantEntryKind: String, Sendable {
    case shellDispatch
    case commandSuggestion
    case explanation
    case fixSuggestion

    var title: String {
        switch self {
        case .shellDispatch: return "Command"
        case .commandSuggestion: return "Suggestion"
        case .explanation: return "Explanation"
        case .fixSuggestion: return "Fix"
        }
    }
}

enum ComposeAssistantEntryStatus: String, Sendable {
    case pending
    case ready
    case failed
    case inserted
    case ran

    var label: String {
        switch self {
        case .pending: return "Thinking"
        case .ready: return "Ready"
        case .failed: return "Failed"
        case .inserted: return "Loaded"
        case .ran: return "Sent"
        }
    }
}

struct ComposeAssistantEntry: Identifiable, Sendable {
    let id: UUID
    let kind: ComposeAssistantEntryKind
    let prompt: String
    var response: String
    var command: String?
    var contextSnippet: String?
    var status: ComposeAssistantEntryStatus
    var errorMessage: String?
    let createdAt: Date

    var runnableCommand: String? {
        guard let command else { return nil }
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("NOTE:") else { return nil }
        return trimmed
    }

    var primaryText: String {
        if let errorMessage, !errorMessage.isEmpty {
            return errorMessage
        }
        if !response.isEmpty {
            return response
        }
        if let command, !command.isEmpty {
            return command
        }
        return prompt
    }

    var usesMonospacedBody: Bool {
        switch kind {
        case .shellDispatch, .commandSuggestion, .fixSuggestion:
            return true
        case .explanation:
            return false
        }
    }

    var canInsert: Bool {
        switch kind {
        case .commandSuggestion, .fixSuggestion:
            return runnableCommand != nil
        case .shellDispatch, .explanation:
            return false
        }
    }

    var canRun: Bool {
        switch kind {
        case .shellDispatch, .commandSuggestion, .fixSuggestion:
            return runnableCommand != nil
        case .explanation:
            return false
        }
    }

    var canExplain: Bool {
        switch kind {
        case .shellDispatch, .commandSuggestion, .fixSuggestion:
            return true
        case .explanation:
            return false
        }
    }

    var canFix: Bool {
        switch kind {
        case .shellDispatch, .commandSuggestion, .fixSuggestion:
            return true
        case .explanation:
            return false
        }
    }
}

@MainActor
@Observable
final class ComposeAssistantState {
    private static let maxEntries = 12

    var mode: ComposeAssistantMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: AppStorageKeys.composeAssistantMode)
        }
    }

    var draftText: String = ""
    var interactions: [ComposeAssistantEntry] = []

    init() {
        let raw = UserDefaults.standard.string(forKey: AppStorageKeys.composeAssistantMode) ?? ComposeAssistantMode.shell.rawValue
        self.mode = ComposeAssistantMode(rawValue: raw) ?? .shell
    }

    var placeholderText: String { mode.placeholderText }
    var isBusy: Bool { interactions.contains(where: { $0.status == .pending }) }
    var latestRunnableEntry: ComposeAssistantEntry? {
        interactions.first(where: { $0.canRun || $0.canExplain || $0.canFix })
    }

    func setDraftText(_ text: String) {
        if draftText != text {
            draftText = text
        }
    }

    @discardableResult
    func addEntry(
        kind: ComposeAssistantEntryKind,
        prompt: String,
        response: String = "",
        command: String? = nil,
        contextSnippet: String? = nil,
        status: ComposeAssistantEntryStatus,
        errorMessage: String? = nil
    ) -> UUID {
        let id = UUID()
        interactions.insert(
            ComposeAssistantEntry(
                id: id,
                kind: kind,
                prompt: prompt,
                response: response,
                command: command,
                contextSnippet: contextSnippet,
                status: status,
                errorMessage: errorMessage,
                createdAt: Date()
            ),
            at: 0
        )
        if interactions.count > Self.maxEntries {
            interactions = Array(interactions.prefix(Self.maxEntries))
        }
        return id
    }

    @discardableResult
    func beginEntry(
        kind: ComposeAssistantEntryKind,
        prompt: String,
        command: String? = nil,
        contextSnippet: String? = nil
    ) -> UUID {
        addEntry(
            kind: kind,
            prompt: prompt,
            response: "",
            command: command,
            contextSnippet: contextSnippet,
            status: .pending
        )
    }

    func finishEntry(id: UUID, response: String, command: String? = nil, contextSnippet: String? = nil) {
        updateEntry(id: id) { entry in
            entry.response = response
            entry.command = command ?? entry.command
            if let contextSnippet, !contextSnippet.isEmpty {
                entry.contextSnippet = contextSnippet
            }
            entry.errorMessage = nil
            entry.status = .ready
        }
    }

    func failEntry(id: UUID, message: String, contextSnippet: String? = nil) {
        updateEntry(id: id) { entry in
            entry.errorMessage = message
            if let contextSnippet, !contextSnippet.isEmpty {
                entry.contextSnippet = contextSnippet
            }
            entry.status = .failed
        }
    }

    func markInserted(id: UUID) {
        updateEntry(id: id) { entry in
            entry.status = .inserted
        }
    }

    func markRan(id: UUID) {
        updateEntry(id: id) { entry in
            entry.status = .ran
        }
    }

    func loadDraft(from id: UUID) -> Bool {
        guard let entry = entry(id: id), let command = entry.runnableCommand else { return false }
        draftText = command
        mode = .shell
        markInserted(id: id)
        return true
    }

    func attachContext(_ snippet: String, to id: UUID) {
        let trimmed = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateEntry(id: id) { entry in
            entry.contextSnippet = trimmed
        }
    }

    func entry(id: UUID) -> ComposeAssistantEntry? {
        interactions.first(where: { $0.id == id })
    }

    func clearHistory() {
        interactions.removeAll()
    }

    private func updateEntry(id: UUID, update: (inout ComposeAssistantEntry) -> Void) {
        guard let index = interactions.firstIndex(where: { $0.id == id }) else { return }
        var updatedInteractions = interactions
        var entry = updatedInteractions[index]
        update(&entry)
        updatedInteractions[index] = entry
        interactions = updatedInteractions
    }
}

enum OllamaCommandServiceError: LocalizedError {
    case invalidEndpoint(String)
    case invalidResponse
    case httpError(Int, String)
    case requestTimedOut(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint(let endpoint):
            return "Invalid Ollama endpoint: \(endpoint)"
        case .invalidResponse:
            return "Ollama returned an invalid response."
        case .httpError(let status, let body):
            return body.isEmpty ? "Ollama request failed with HTTP \(status)." : "Ollama request failed with HTTP \(status): \(body)"
        case .requestTimedOut(let endpoint):
            return "Ollama timed out at \(endpoint). Check the endpoint, model, or server load."
        case .transport(let message):
            return message
        }
    }
}

private struct OllamaGenerateRequest: Encodable {
    let model: String
    let prompt: String
    let stream: Bool
    let options: OllamaOptions
}

private struct OllamaOptions: Encodable {
    let temperature: Double
}

private struct OllamaGenerateResponse: Decodable {
    let response: String
}

private struct OllamaTagsResponse: Decodable {
    let models: [OllamaTag]
}

private struct OllamaTag: Decodable {
    let name: String
}

enum OllamaCommandService {
    static let defaultEndpoint = "http://127.0.0.1:11434"
    static let defaultModel = "qwen2.5-coder:7b"
    private static let requestTimeout: TimeInterval = 45

    static func currentEndpoint() -> String {
        let value = UserDefaults.standard.string(forKey: AppStorageKeys.ollamaEndpoint)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value! : defaultEndpoint
    }

    static func currentModel() -> String {
        let value = UserDefaults.standard.string(forKey: AppStorageKeys.ollamaModel)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value! : defaultModel
    }

    static func currentLaunchCommand() -> String {
        launchCommand(endpoint: currentEndpoint(), model: currentModel())
    }

    static func testConnection(endpoint: String, model: String) async throws -> String {
        let resolvedEndpoint = resolveEndpoint(endpoint)
        let resolvedModel = resolveModel(model)

        guard var url = URL(string: resolvedEndpoint) else {
            throw OllamaCommandServiceError.invalidEndpoint(resolvedEndpoint)
        }
        url.append(path: "api/tags")

        var httpRequest = URLRequest(url: url)
        httpRequest.httpMethod = "GET"
        httpRequest.timeoutInterval = requestTimeout

        let (data, _) = try await performRequest(httpRequest, endpoint: resolvedEndpoint)
        let tags = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
        let availableModels = tags.models.map(\.name)

        if availableModels.contains(resolvedModel) {
            return "Connected to \(resolvedEndpoint). Model \(resolvedModel) is available."
        }

        if availableModels.isEmpty {
            return "Connected to \(resolvedEndpoint), but the server did not report any installed models."
        }

        let preview = availableModels.prefix(8).joined(separator: ", ")
        return "Connected to \(resolvedEndpoint), but model \(resolvedModel) was not found. Available models: \(preview)"
    }

    static func launchCommand(endpoint: String, model: String) -> String {
        let resolvedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? defaultEndpoint
            : endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedModel = model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? defaultModel
            : model.trimmingCharacters(in: .whitespacesAndNewlines)

        if resolvedEndpoint == defaultEndpoint {
            return "ollama run \(shellQuote(resolvedModel))"
        }

        return "OLLAMA_HOST=\(shellQuote(resolvedEndpoint)) ollama run \(shellQuote(resolvedModel))"
    }

    static func generateCommand(for request: String, pwd: String?) async throws -> String {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let prompt = buildCommandPrompt(request: request, pwd: pwd, shell: shell)
        return try await sendPrompt(prompt, temperature: 0.15)
    }

    static func explainCommandOutput(command: String?, output: String, pwd: String?) async throws -> String {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let prompt = buildExplainPrompt(command: command, output: output, pwd: pwd, shell: shell)
        return try await sendPrompt(prompt, temperature: 0.2)
    }

    static func suggestFix(command: String?, output: String, pwd: String?) async throws -> String {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let prompt = buildFixPrompt(command: command, output: output, pwd: pwd, shell: shell)
        return try await sendPrompt(prompt, temperature: 0.15)
    }

    private static func sendPrompt(_ prompt: String, temperature: Double) async throws -> String {
        let endpoint = currentEndpoint()
        guard var url = URL(string: endpoint) else {
            throw OllamaCommandServiceError.invalidEndpoint(endpoint)
        }
        url.append(path: "api/generate")

        var httpRequest = URLRequest(url: url)
        httpRequest.httpMethod = "POST"
        httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        httpRequest.timeoutInterval = requestTimeout

        let body = OllamaGenerateRequest(
            model: currentModel(),
            prompt: prompt,
            stream: false,
            options: OllamaOptions(temperature: temperature)
        )
        httpRequest.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await performRequest(httpRequest, endpoint: endpoint)
        guard response is HTTPURLResponse else {
            throw OllamaCommandServiceError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data)
        let cleaned = cleanResponse(decoded.response)
        guard !cleaned.isEmpty else {
            throw OllamaCommandServiceError.invalidResponse
        }
        return cleaned
    }

    private static func performRequest(
        _ httpRequest: URLRequest,
        endpoint: String
    ) async throws -> (Data, URLResponse) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = requestTimeout
        let session = URLSession(configuration: configuration)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: httpRequest)
        } catch let error as URLError where error.code == .timedOut {
            throw OllamaCommandServiceError.requestTimedOut(endpoint)
        } catch let error as URLError where error.code == .cannotConnectToHost || error.code == .cannotFindHost || error.code == .networkConnectionLost || error.code == .notConnectedToInternet {
            throw OllamaCommandServiceError.transport("Could not reach Ollama at \(endpoint): \(error.localizedDescription)")
        } catch {
            throw OllamaCommandServiceError.transport("Ollama request failed: \(error.localizedDescription)")
        }

        guard let http = response as? HTTPURLResponse else {
            throw OllamaCommandServiceError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw OllamaCommandServiceError.httpError(http.statusCode, bodyText)
        }
        return (data, response)
    }

    private static func buildCommandPrompt(request: String, pwd: String?, shell: String) -> String {
        let cwd = pwd ?? "(unknown)"
        return """
        You are Calyx, a terminal command assistant embedded in a macOS terminal app.

        Return the single best shell command for the user's request.

        Rules:
        - Output only the command text when a command is appropriate.
        - Do not use markdown fences, bullets, or explanation.
        - Prefer one-liners.
        - Preserve safety. Do not propose destructive commands unless the user's intent clearly requires it.
        - If a command would be unsafe, ambiguous, or the request is not really a shell command task, respond with a brief plain-English sentence prefixed by NOTE:

        Context:
        - Current working directory: \(cwd)
        - Shell: \(shell)

        User request:
        \(request)
        """
    }

    private static func buildExplainPrompt(command: String?, output: String, pwd: String?, shell: String) -> String {
        let cwd = pwd ?? "(unknown)"
        let commandText = command?.isEmpty == false ? command! : "(unknown command)"
        return """
        You are Calyx, a terminal assistant embedded in a macOS terminal app.

        Explain what happened in the terminal output below.

        Rules:
        - Respond in plain English.
        - Be concise and concrete.
        - Mention the most likely cause first.
        - End with the next thing the user should try.
        - Do not use markdown fences.

        Context:
        - Current working directory: \(cwd)
        - Shell: \(shell)
        - Command: \(commandText)

        Terminal output:
        \(trimmedContext(output))
        """
    }

    private static func buildFixPrompt(command: String?, output: String, pwd: String?, shell: String) -> String {
        let cwd = pwd ?? "(unknown)"
        let commandText = command?.isEmpty == false ? command! : "(unknown command)"
        return """
        You are Calyx, a terminal command assistant embedded in a macOS terminal app.

        The command below failed. Return the single best replacement shell command.

        Rules:
        - Output only the replacement command text when a command is appropriate.
        - Do not use markdown fences or explanation.
        - Prefer one-liners.
        - Keep the fix as close as possible to the original intent.
        - If the output is ambiguous or a command would be unsafe, respond with a brief plain-English sentence prefixed by NOTE:

        Context:
        - Current working directory: \(cwd)
        - Shell: \(shell)
        - Original command: \(commandText)

        Failure output:
        \(trimmedContext(output))
        """
    }

    private static func trimmedContext(_ text: String, limit: Int = 3_000) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        let start = trimmed.index(trimmed.endIndex, offsetBy: -limit)
        return String(trimmed[start...])
    }

    private static func cleanResponse(_ response: String) -> String {
        var text = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text
                .replacingOccurrences(of: "```bash", with: "")
                .replacingOccurrences(of: "```sh", with: "")
                .replacingOccurrences(of: "```shell", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    private static func resolveEndpoint(_ endpoint: String) -> String {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultEndpoint : trimmed
    }

    private static func resolveModel(_ model: String) -> String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultModel : trimmed
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
