import Foundation
import JSONSchema

public enum SKIAgentSessionError: Error, LocalizedError, Equatable {
    case promptAlreadyRunning
    case invalidForkEntryIndex(Int)

    public var errorDescription: String? {
        switch self {
        case .promptAlreadyRunning:
            return "A prompt is already running in this session."
        case .invalidForkEntryIndex(let index):
            return "Invalid fork entry index: \(index)"
        }
    }
}

/// A lightweight ACP-oriented session facade built on top of `SKILanguageModelSession`.
public actor SKIAgentSession {
    public typealias ForkableUserMessage = SKITranscript.ForkableUserMessage

    public enum StreamingBehavior: Sendable {
        case reject
        case steer
        case followUp
    }

    public enum PendingMessageSource: String, Sendable, Equatable {
        case promptFollowUp = "prompt_follow_up"
        case steer
        case followUp = "follow_up"
    }

    public enum ToolSource: String, Sendable {
        case native
        case mcp
    }

    public struct ToolDescriptor: Sendable, Equatable {
        public var name: String
        public var description: String
        public var shortDescription: String
        public var isEnabled: Bool
        public var source: ToolSource
        public var parameters: [String: JSONValue]?

        public init(
            name: String,
            description: String,
            shortDescription: String,
            isEnabled: Bool,
            source: ToolSource,
            parameters: [String: JSONValue]? = nil
        ) {
            self.name = name
            self.description = description
            self.shortDescription = shortDescription
            self.isEnabled = isEnabled
            self.source = source
            self.parameters = parameters
        }
    }

    public struct SessionStats: Sendable, Equatable {
        public struct PendingBreakdown: Sendable, Equatable {
            public var promptFollowUp: Int
            public var steer: Int
            public var followUp: Int

            public init(promptFollowUp: Int, steer: Int, followUp: Int) {
                self.promptFollowUp = promptFollowUp
                self.steer = steer
                self.followUp = followUp
            }
        }

        public var sessionId: String
        public var userMessages: Int
        public var assistantMessages: Int
        public var toolCalls: Int
        public var toolResults: Int
        public var totalEntries: Int
        public var pendingMessages: Int
        public var lastUpdatedAt: Date?
        public var pendingBreakdown: PendingBreakdown

        public init(
            sessionId: String,
            userMessages: Int,
            assistantMessages: Int,
            toolCalls: Int,
            toolResults: Int,
            totalEntries: Int,
            pendingMessages: Int,
            lastUpdatedAt: Date?,
            pendingBreakdown: PendingBreakdown
        ) {
            self.sessionId = sessionId
            self.userMessages = userMessages
            self.assistantMessages = assistantMessages
            self.toolCalls = toolCalls
            self.toolResults = toolResults
            self.totalEntries = totalEntries
            self.pendingMessages = pendingMessages
            self.lastUpdatedAt = lastUpdatedAt
            self.pendingBreakdown = pendingBreakdown
        }
    }

    public struct PendingMessageDescriptor: Sendable, Equatable {
        public enum Status: String, Sendable, Equatable {
            case queued
            case resolved
            case failed
        }

        public var source: PendingMessageSource
        public var textPreview: String
        public var status: Status

        public init(source: PendingMessageSource, textPreview: String, status: Status = .queued) {
            self.source = source
            self.textPreview = textPreview
            self.status = status
        }
    }

    public static let defaultPendingPreviewMaxLength = 120
    public static let resolvedPendingHistoryLimit = 20

    public struct ClearPendingStateResult: Sendable, Equatable {
        public var queuedRemoved: Int
        public var resolvedRemoved: Int
        public var activePromptCancelled: Bool

        public init(queuedRemoved: Int, resolvedRemoved: Int, activePromptCancelled: Bool) {
            self.queuedRemoved = queuedRemoved
            self.resolvedRemoved = resolvedRemoved
            self.activePromptCancelled = activePromptCancelled
        }
    }

    private let id: String
    private let client: SKILanguageModelClient
    private let modelSession: SKILanguageModelSession

    private enum PendingPrompt {
        case awaiting(
            prompt: SKIPrompt,
            source: PendingMessageSource,
            continuation: CheckedContinuation<String, Error>
        )
        case fireAndForget(prompt: SKIPrompt, source: PendingMessageSource)
    }

    private struct ResolvedPendingItem {
        var source: PendingMessageSource
        var text: String
        var status: PendingMessageDescriptor.Status
    }

    private var registeredTools: [String: any SKITool] = [:]
    private var registeredMCPTools: [String: SKIMCPTool] = [:]
    private var activePromptTask: Task<String, Error>?
    private var pendingPrompts: [PendingPrompt] = []
    private var resolvedPendingHistory: [ResolvedPendingItem] = []

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

    public func prompt(
        _ text: String,
        streamingBehavior: StreamingBehavior
    ) async throws -> String {
        try await prompt(SKIPrompt(stringLiteral: text), streamingBehavior: streamingBehavior)
    }

    public func prompt(_ promptValue: SKIPrompt) async throws -> String {
        try await prompt(promptValue, streamingBehavior: .reject)
    }

    public func prompt(
        _ prompt: SKIPrompt,
        streamingBehavior: StreamingBehavior
    ) async throws -> String {
        if activePromptTask != nil {
            switch streamingBehavior {
            case .reject:
                throw SKIAgentSessionError.promptAlreadyRunning
            case .steer, .followUp:
                let source: PendingMessageSource = streamingBehavior == .steer ? .steer : .promptFollowUp
                return try await withCheckedThrowingContinuation { continuation in
                    pendingPrompts.append(
                        .awaiting(prompt: prompt, source: source, continuation: continuation)
                    )
                }
            }
        }

        let task = Task<String, Error> {
            try await self.runPromptLoop(startingWith: prompt)
        }
        activePromptTask = task
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

    public func steer(_ text: String) {
        enqueueFireAndForget(SKIPrompt(stringLiteral: text), source: .steer)
    }

    public func followUp(_ text: String) {
        enqueueFireAndForget(SKIPrompt(stringLiteral: text), source: .followUp)
    }

    public func pendingMessageCount() -> Int {
        pendingPrompts.count
    }

    public func pendingMessages(
        maxLength: Int = SKIAgentSession.defaultPendingPreviewMaxLength,
        includeResolved: Bool = false
    ) -> [PendingMessageDescriptor] {
        let previewMaxLength = max(1, maxLength)
        let queued = pendingPrompts.map { item in
            switch item {
            case .awaiting(let prompt, let source, _):
                return PendingMessageDescriptor(
                    source: source,
                    textPreview: promptPreview(prompt, maxLength: previewMaxLength),
                    status: .queued
                )
            case .fireAndForget(let prompt, let source):
                return PendingMessageDescriptor(
                    source: source,
                    textPreview: promptPreview(prompt, maxLength: previewMaxLength),
                    status: .queued
                )
            }
        }
        guard includeResolved else { return queued }
        let resolved = resolvedPendingHistory.map { item in
            PendingMessageDescriptor(
                source: item.source,
                textPreview: truncatePreview(item.text, maxLength: previewMaxLength),
                status: item.status
            )
        }
        return queued + resolved
    }

    public func clearPendingHistory() {
        resolvedPendingHistory.removeAll(keepingCapacity: false)
    }

    public func clearPendingState(cancelActivePrompt: Bool = false) -> ClearPendingStateResult {
        let queuedItems = pendingPrompts
        pendingPrompts.removeAll(keepingCapacity: false)
        for item in queuedItems {
            guard case .awaiting(_, _, let continuation) = item else { continue }
            continuation.resume(throwing: CancellationError())
        }
        let resolvedRemovedCount = resolvedPendingHistory.count
        resolvedPendingHistory.removeAll(keepingCapacity: false)
        let shouldCancelActivePrompt = cancelActivePrompt && activePromptTask != nil
        if cancelActivePrompt {
            activePromptTask?.cancel()
        }
        return .init(
            queuedRemoved: queuedItems.count,
            resolvedRemoved: resolvedRemovedCount,
            activePromptCancelled: shouldCancelActivePrompt
        )
    }

    public func register(tool: any SKITool) async {
        registeredTools[tool.name] = tool
        await modelSession.register(tool: tool)
    }

    public func register(mcpTool: SKIMCPTool) async {
        registeredMCPTools[mcpTool.name] = mcpTool
        await modelSession.register(mcpTool: mcpTool)
    }

    public func unregister(toolNamed name: String) async {
        registeredTools.removeValue(forKey: name)
        await modelSession.unregister(toolNamed: name)
    }

    public func unregister(mcpToolNamed name: String) async {
        registeredMCPTools.removeValue(forKey: name)
        await modelSession.unregister(mcpToolNamed: name)
    }

    public func toolDescriptors() -> [ToolDescriptor] {
        let native: [ToolDescriptor] = registeredTools.values.map { tool in
            let metadata = tool.metadata
            return .init(
                name: metadata.name,
                description: metadata.description,
                shortDescription: metadata.shortDescription,
                isEnabled: metadata.isEnabled,
                source: .native,
                parameters: metadata.parameters
            )
        }
        let mcp: [ToolDescriptor] = registeredMCPTools.values.map { tool in
            .init(
                name: tool.name,
                description: tool.description ?? "",
                shortDescription: tool.description ?? "",
                isEnabled: true,
                source: .mcp,
                parameters: nil
            )
        }
        return (native + mcp).sorted { lhs, rhs in
            if lhs.source != rhs.source {
                return lhs.source.rawValue < rhs.source.rawValue
            }
            return lhs.name < rhs.name
        }
    }

    public func activeToolNames() -> [String] {
        let native = registeredTools.values.filter(\.isEnabled).map(\.name)
        let mcp = registeredMCPTools.keys.map { $0 }
        return Array(Set(native + mcp)).sorted()
    }

    public func stats() async -> SessionStats {
        let transcript = await modelSession.transcript
        let entries = await transcript.entries
        let lastUpdatedAt = await transcript.lastUpdatedAt
        var userMessages = 0
        var assistantMessages = 0
        var toolCalls = 0
        var toolResults = 0
        var promptFollowUpPending = 0
        var steerPending = 0
        var followUpPending = 0

        for entry in entries {
            switch entry {
            case .prompt(let message), .message(let message), .response(let message):
                switch message.role {
                case "user":
                    userMessages += 1
                case "assistant":
                    assistantMessages += 1
                default:
                    break
                }
            case .toolCalls:
                toolCalls += 1
            case .toolOutput:
                toolResults += 1
            }
        }
        for item in pendingPrompts {
            let source: PendingMessageSource
            switch item {
            case .awaiting(_, let s, _):
                source = s
            case .fireAndForget(_, let s):
                source = s
            }
            switch source {
            case .promptFollowUp:
                promptFollowUpPending += 1
            case .steer:
                steerPending += 1
            case .followUp:
                followUpPending += 1
            }
        }

        return .init(
            sessionId: id,
            userMessages: userMessages,
            assistantMessages: assistantMessages,
            toolCalls: toolCalls,
            toolResults: toolResults,
            totalEntries: entries.count,
            pendingMessages: pendingPrompts.count,
            lastUpdatedAt: lastUpdatedAt,
            pendingBreakdown: .init(
                promptFollowUp: promptFollowUpPending,
                steer: steerPending,
                followUp: followUpPending
            )
        )
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

    public func forkableUserMessages() async -> [ForkableUserMessage] {
        let transcript = await modelSession.transcript
        return await transcript.forkableUserMessages()
    }

    public func fork(
        fromUserEntryIndex index: Int,
        id: String = "sess_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
    ) async throws -> SKIAgentSession {
        let transcript = await modelSession.transcript
        let snapshot: [SKITranscript.Entry]
        do {
            snapshot = try await transcript.entriesForFork(fromUserEntryIndex: index)
        } catch {
            throw SKIAgentSessionError.invalidForkEntryIndex(index)
        }
        return try await makeForkSession(id: id, snapshot: snapshot)
    }

    public func fork(
        id: String = "sess_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
    ) async throws -> SKIAgentSession {
        let snapshot = await transcriptEntries()
        return try await makeForkSession(id: id, snapshot: snapshot)
    }

    private func makeForkSession(
        id: String,
        snapshot: [SKITranscript.Entry]
    ) async throws -> SKIAgentSession {
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

    private func enqueueFireAndForget(_ prompt: SKIPrompt, source: PendingMessageSource) {
        guard activePromptTask == nil else {
            pendingPrompts.append(.fireAndForget(prompt: prompt, source: source))
            return
        }
        let task = Task<String, Error> {
            do {
                let result = try await self.runPromptLoop(startingWith: prompt)
                self.appendResolvedPending(source: source, prompt: prompt, status: .resolved)
                return result
            } catch {
                self.appendResolvedPending(source: source, prompt: prompt, status: .failed)
                throw error
            }
        }
        activePromptTask = task
        Task {
            _ = try? await task.value
        }
    }

    private func runPromptLoop(startingWith firstPrompt: SKIPrompt) async throws -> String {
        defer { activePromptTask = nil }
        do {
            let firstResult = try await modelSession.respond(to: firstPrompt)
            while !pendingPrompts.isEmpty {
                let item = pendingPrompts.removeFirst()
                switch item {
                case .fireAndForget(let prompt, let source):
                    do {
                        _ = try await modelSession.respond(to: prompt)
                        appendResolvedPending(source: source, prompt: prompt, status: .resolved)
                    } catch {
                        appendResolvedPending(source: source, prompt: prompt, status: .failed)
                        throw error
                    }
                case .awaiting(let prompt, let source, let continuation):
                    do {
                        let output = try await modelSession.respond(to: prompt)
                        continuation.resume(returning: output)
                        appendResolvedPending(source: source, prompt: prompt, status: .resolved)
                    } catch {
                        continuation.resume(throwing: error)
                        appendResolvedPending(source: source, prompt: prompt, status: .failed)
                    }
                }
            }
            return firstResult
        } catch {
            failPendingPrompts(with: error)
            throw error
        }
    }

    private func failPendingPrompts(with error: Error) {
        let items = pendingPrompts
        pendingPrompts.removeAll(keepingCapacity: false)
        for item in items {
            switch item {
            case .awaiting(let prompt, let source, let continuation):
                continuation.resume(throwing: error)
                appendResolvedPending(source: source, prompt: prompt, status: .failed)
            case .fireAndForget(let prompt, let source):
                appendResolvedPending(source: source, prompt: prompt, status: .failed)
            }
        }
    }

    private func appendResolvedPending(
        source: PendingMessageSource,
        prompt: SKIPrompt,
        status: PendingMessageDescriptor.Status
    ) {
        let item = ResolvedPendingItem(
            source: source,
            text: promptText(prompt),
            status: status
        )
        resolvedPendingHistory.append(item)
        if resolvedPendingHistory.count > SKIAgentSession.resolvedPendingHistoryLimit {
            resolvedPendingHistory.removeFirst(resolvedPendingHistory.count - SKIAgentSession.resolvedPendingHistoryLimit)
        }
    }

    private func promptText(_ prompt: SKIPrompt) -> String {
        let raw: String
        switch prompt.message {
        case .user(let content, _):
            switch content {
            case .text(let text):
                raw = text
            case .parts(let parts):
                let texts = parts.compactMap { part -> String? in
                    if case .text(let text) = part {
                        return text
                    }
                    return nil
                }
                raw = texts.joined(separator: "\n")
            }
        default:
            raw = ""
        }
        return raw.replacingOccurrences(of: "\r\n", with: "\n")
    }

    private func promptPreview(_ prompt: SKIPrompt, maxLength: Int) -> String {
        truncatePreview(promptText(prompt), maxLength: maxLength)
    }

    private func truncatePreview(_ text: String, maxLength: Int) -> String {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        if normalized.count <= maxLength {
            return normalized
        }
        let slice = normalized.prefix(maxLength)
        return String(slice) + "..."
    }
}
