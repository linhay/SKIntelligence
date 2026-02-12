import Foundation

public enum SKIAgentSessionError: Error, LocalizedError {
    case promptAlreadyRunning

    public var errorDescription: String? {
        switch self {
        case .promptAlreadyRunning:
            return "A prompt is already running in this session."
        }
    }
}

/// A lightweight ACP-oriented session facade built on top of `SKILanguageModelSession`.
public actor SKIAgentSession {
    private let id: String
    private let client: SKILanguageModelClient
    private let modelSession: SKILanguageModelSession

    private var registeredTools: [String: any SKITool] = [:]
    private var registeredMCPTools: [String: SKIMCPTool] = [:]
    private var activePromptTask: Task<String, Error>?

    public init(
        id: String = "sess_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))",
        client: SKILanguageModelClient,
        transcript: SKITranscript = SKITranscript(),
        tools: [any SKITool] = []
    ) {
        self.id = id
        self.client = client
        self.modelSession = SKILanguageModelSession(client: client, transcript: transcript, tools: tools)
        for tool in tools {
            self.registeredTools[tool.name] = tool
        }
    }

    private init(
        id: String,
        client: SKILanguageModelClient,
        modelSession: SKILanguageModelSession,
        registeredTools: [String: any SKITool],
        registeredMCPTools: [String: SKIMCPTool]
    ) {
        self.id = id
        self.client = client
        self.modelSession = modelSession
        self.registeredTools = registeredTools
        self.registeredMCPTools = registeredMCPTools
    }

    public func sessionId() -> String {
        id
    }

    public func prompt(_ text: String) async throws -> String {
        try await prompt(SKIPrompt(stringLiteral: text))
    }

    public func prompt(_ prompt: SKIPrompt) async throws -> String {
        if activePromptTask != nil {
            throw SKIAgentSessionError.promptAlreadyRunning
        }

        let task = Task<String, Error> {
            try await self.modelSession.respond(to: prompt)
        }
        activePromptTask = task
        defer { activePromptTask = nil }
        return try await task.value
    }

    public func stream(_ text: String) async throws -> SKIResponseStream {
        try await modelSession.streamResponse(to: text)
    }

    public func stream(_ prompt: SKIPrompt) async throws -> SKIResponseStream {
        try await modelSession.streamResponse(to: prompt)
    }

    public func cancelActivePrompt() {
        activePromptTask?.cancel()
    }

    public func register(tool: any SKITool) async {
        registeredTools[tool.name] = tool
        await modelSession.register(tool: tool)
    }

    public func register(mcpTool: SKIMCPTool) async {
        registeredMCPTools[mcpTool.name] = mcpTool
        await modelSession.register(mcpTool: mcpTool)
    }

    public func transcriptEntries() async -> [SKITranscript.Entry] {
        let transcript = await modelSession.transcript
        return await transcript.entries
    }

    public func enableJSONLPersistence(
        fileURL: URL,
        configuration: SKITranscript.JSONLPersistenceConfiguration = .init()
    ) async throws {
        let transcript = await modelSession.transcript
        try await transcript.enableJSONLPersistence(
            sessionId: id,
            fileURL: fileURL,
            configuration: configuration
        )
    }

    public func resume(with entries: [SKITranscript.Entry]) async throws {
        let transcript = await modelSession.transcript
        await transcript.replaceEntries(entries)
    }

    public func fork(
        id: String = "sess_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
    ) async throws -> SKIAgentSession {
        let snapshot = await transcriptEntries()
        let forkTranscript = SKITranscript()
        await forkTranscript.replaceEntries(snapshot)

        let forkSession = SKILanguageModelSession(
            client: client,
            transcript: forkTranscript,
            tools: Array(registeredTools.values)
        )
        for mcpTool in registeredMCPTools.values {
            await forkSession.register(mcpTool: mcpTool)
        }

        return SKIAgentSession(
            id: id,
            client: client,
            modelSession: forkSession,
            registeredTools: registeredTools,
            registeredMCPTools: registeredMCPTools
        )
    }
}
