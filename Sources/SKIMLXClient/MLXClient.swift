import Foundation
import HTTPTypes
import JSONSchema
import SKIntelligence

public actor MLXClient: SKILanguageModelClient {
    public typealias TelemetrySink = @Sendable (MLXClientTelemetryEvent) async -> Void

    public struct Configuration: Sendable {
        public var modelID: String
        public var revision: String
        public var toolCallEnabled: Bool
        public var requestTimeout: TimeInterval
        public var defaultSeed: Int?
        public var defaultStop: [String]
        public var telemetrySink: TelemetrySink?

        public init(
            modelID: String = "mlx-community/Qwen3-4B-4bit",
            revision: String = "main",
            toolCallEnabled: Bool = true,
            requestTimeout: TimeInterval = 300,
            defaultSeed: Int? = nil,
            defaultStop: [String] = [],
            telemetrySink: TelemetrySink? = nil
        ) {
            self.modelID = modelID
            self.revision = revision
            self.toolCallEnabled = toolCallEnabled
            self.requestTimeout = requestTimeout
            self.defaultSeed = defaultSeed
            self.defaultStop = defaultStop
            self.telemetrySink = telemetrySink
        }
    }

    private let configuration: Configuration
    private let backend: any MLXClientBackend
    private var didLoadModel = false

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
        self.backend = DefaultMLXBackend()
    }

    init(
        configuration: Configuration = .init(),
        backend: any MLXClientBackend
    ) {
        self.configuration = configuration
        self.backend = backend
    }

    public var isModelLoaded: Bool {
        didLoadModel
    }

    public func respond(_ body: ChatRequestBody) async throws -> sending SKIResponse<ChatResponseBody> {
        try Task.checkCancellation()
        let startedAt = Date()
        let request = MLXClientRequest(
            messages: body.messages,
            tools: configuration.toolCallEnabled ? body.tools : nil,
            options: .from(
                body: body,
                defaultSeed: configuration.defaultSeed,
                defaultStop: configuration.defaultStop
            )
        )
        await emitIgnoredOptionsIfNeeded(request.options, requestKind: "respond")
        try await ensureLoaded()
        do {
            let events = try await withTimeout(self.configuration.requestTimeout) {
                try await self.backend.generate(request: request, configuration: self.configuration)
            }
            let response = try makeResponse(from: events, options: request.options)
            let summary = Self.summarizeEvents(events)
            await emitTelemetry(
                .respondFinished(
                    modelID: configuration.modelID,
                    durationSeconds: Date().timeIntervalSince(startedAt),
                    outputCharacters: summary.outputCharacters,
                    promptTokens: summary.promptTokens,
                    completionTokens: summary.completionTokens,
                    totalTokens: summary.totalTokens,
                    timedOut: false,
                    cancelled: false
                )
            )
            return response
        } catch {
            let state = telemetryState(for: error)
            await emitTelemetry(
                .respondFinished(
                    modelID: configuration.modelID,
                    durationSeconds: Date().timeIntervalSince(startedAt),
                    outputCharacters: 0,
                    promptTokens: nil,
                    completionTokens: nil,
                    totalTokens: nil,
                    timedOut: state.timedOut,
                    cancelled: state.cancelled
                )
            )
            throw error
        }
    }

    public func streamingRespond(_ body: ChatRequestBody) async throws -> SKIResponseStream {
        try Task.checkCancellation()
        let startedAt = Date()
        let request = MLXClientRequest(
            messages: body.messages,
            tools: configuration.toolCallEnabled ? body.tools : nil,
            options: .from(
                body: body,
                defaultSeed: configuration.defaultSeed,
                defaultStop: configuration.defaultStop
            )
        )
        await emitIgnoredOptionsIfNeeded(request.options, requestKind: "stream")
        try await ensureLoaded()
        let requestTimeout = self.configuration.requestTimeout
        let telemetrySink = self.configuration.telemetrySink
        let modelID = self.configuration.modelID
        let source = try await withTimeout(self.configuration.requestTimeout) {
            try await self.backend.streamGenerate(request: request, configuration: self.configuration)
        }
        return SKIResponseStream {
            AsyncThrowingStream { continuation in
                let producer = Task {
                    var firstChunkLatency: TimeInterval?
                    var chunkCount = 0
                    var outputCharacters = 0
                    var promptTokens: Int?
                    var completionTokens: Int?
                    var nextToolCallIndex = 0
                    let stopSequences = request.options.stopSequences
                    let buffer = StreamingStopBuffer(stopSequences: stopSequences)
                    var didStopBySequence = false
                    do {
                        let iterator = MLXEventIteratorBox(source.makeAsyncIterator())
                        while let event = try await withTimeout(requestTimeout, operation: {
                            try await iterator.next()
                        }) {
                            try Task.checkCancellation()
                            if firstChunkLatency == nil {
                                firstChunkLatency = Date().timeIntervalSince(startedAt)
                            }
                            switch event {
                            case .text(let text):
                                if stopSequences.isEmpty {
                                    chunkCount += 1
                                    outputCharacters += text.count
                                    continuation.yield(.init(text: text))
                                } else {
                                    let output = await buffer.consume(text)
                                    if !output.prefix.isEmpty {
                                        chunkCount += 1
                                        outputCharacters += output.prefix.count
                                        continuation.yield(.init(text: output.prefix))
                                    }
                                    if output.didStop {
                                        didStopBySequence = true
                                        break
                                    }
                                }
                            case .toolCall(let name, let argumentsRaw):
                                chunkCount += 1
                                let toolCallIndex = nextToolCallIndex
                                nextToolCallIndex += 1
                                continuation.yield(
                                    .init(
                                        toolCallDeltas: [
                                            .init(
                                                index: toolCallIndex,
                                                id: nil,
                                                type: "function",
                                                function: .init(name: name, arguments: argumentsRaw)
                                            )
                                        ]
                                    )
                                )
                            case .info(let prompt, let completion):
                                chunkCount += 1
                                promptTokens = prompt
                                completionTokens = completion
                                continuation.yield(
                                    .init(
                                        usage: Self.makeUsage(
                                            promptTokens: prompt,
                                            completionTokens: completion
                                        ))
                                )
                            case .delay(let nanos):
                                try await Task.sleep(nanoseconds: nanos)
                            }
                            if didStopBySequence {
                                break
                            }
                        }
                        if !stopSequences.isEmpty, !didStopBySequence {
                            let tail = await buffer.flush()
                            if !tail.isEmpty {
                                chunkCount += 1
                                outputCharacters += tail.count
                                continuation.yield(.init(text: tail))
                            }
                        }
                        if let telemetrySink {
                            await telemetrySink(
                                .streamFinished(
                                    modelID: modelID,
                                    durationSeconds: Date().timeIntervalSince(startedAt),
                                    firstChunkLatencySeconds: firstChunkLatency,
                                    chunkCount: chunkCount,
                                    outputCharacters: outputCharacters,
                                    promptTokens: promptTokens,
                                    completionTokens: completionTokens,
                                    totalTokens: Self.totalTokens(promptTokens: promptTokens, completionTokens: completionTokens),
                                    timedOut: false,
                                    cancelled: false
                                )
                            )
                        }
                        continuation.finish()
                    } catch {
                        if let telemetrySink {
                            let state = telemetryState(for: error)
                            await telemetrySink(
                                .streamFinished(
                                    modelID: modelID,
                                    durationSeconds: Date().timeIntervalSince(startedAt),
                                    firstChunkLatencySeconds: firstChunkLatency,
                                    chunkCount: chunkCount,
                                    outputCharacters: outputCharacters,
                                    promptTokens: promptTokens,
                                    completionTokens: completionTokens,
                                    totalTokens: Self.totalTokens(promptTokens: promptTokens, completionTokens: completionTokens),
                                    timedOut: state.timedOut,
                                    cancelled: state.cancelled
                                )
                            )
                        }
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in
                    producer.cancel()
                }
            }
        }
    }
}

extension MLXClient {
    private func ensureLoaded() async throws {
        if didLoadModel { return }
        let startedAt = Date()
        try await backend.ensureLoaded(configuration: configuration)
        didLoadModel = true
        await emitTelemetry(
            .modelLoaded(
                modelID: configuration.modelID,
                revision: configuration.revision,
                durationSeconds: Date().timeIntervalSince(startedAt)
            )
        )
    }

    private func makeResponse(
        from events: [MLXClientEvent],
        options: MLXRequestOptions
    ) throws -> SKIResponse<ChatResponseBody> {
        var text = ""
        var toolCalls = [[String: Any]]()
        var promptTokens: Int?
        var completionTokens: Int?

        for event in events {
            switch event {
            case .text(let value):
                text += value
            case .toolCall(let name, let argumentsRaw):
                let function: [String: Any] = [
                    "name": name,
                    "arguments": argumentsRaw,
                ]
                toolCalls.append([
                    "id": "call_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))",
                    "type": "function",
                    "function": function,
                ])
            case .info(let prompt, let completion):
                promptTokens = prompt
                completionTokens = completion
            case .delay:
                break
            }
        }
        if !options.stopSequences.isEmpty {
            text = truncateTextByStopSequences(text, stopSequences: options.stopSequences)
        }

        var message = [String: Any]()
        message["role"] = "assistant"
        if !toolCalls.isEmpty {
            message["tool_calls"] = toolCalls
        } else {
            message["content"] = text
        }

        var root = [String: Any]()
        root["choices"] = [[
            "finish_reason": toolCalls.isEmpty ? "stop" : "tool_calls",
            "message": message,
        ]]
        root["created"] = Int(Date().timeIntervalSince1970)
        root["model"] = configuration.modelID

        if let usage = Self.usageJSON(promptTokens: promptTokens, completionTokens: completionTokens) {
            root["usage"] = usage
        }

        let data = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        return try SKIResponse<ChatResponseBody>(
            httpResponse: HTTPResponse(status: .ok),
            data: data
        )
    }

    private static func usageJSON(promptTokens: Int?, completionTokens: Int?) -> [String: Any]? {
        guard let promptTokens, let completionTokens else { return nil }
        return [
            "prompt_tokens": promptTokens,
            "completion_tokens": completionTokens,
            "total_tokens": promptTokens + completionTokens,
        ]
    }

    private static func makeUsage(promptTokens: Int, completionTokens: Int) -> ChatUsage {
        let usage = usageJSON(promptTokens: promptTokens, completionTokens: completionTokens) ?? [:]
        let data = (try? JSONSerialization.data(withJSONObject: usage, options: [.sortedKeys])) ?? Data()
        return (try? JSONDecoder().decode(ChatUsage.self, from: data))
            ?? (try! JSONDecoder().decode(ChatUsage.self, from: Data("{}".utf8)))
    }

    private static func totalTokens(promptTokens: Int?, completionTokens: Int?) -> Int? {
        guard let promptTokens, let completionTokens else { return nil }
        return promptTokens + completionTokens
    }

    private static func summarizeEvents(_ events: [MLXClientEvent]) -> (
        outputCharacters: Int,
        promptTokens: Int?,
        completionTokens: Int?,
        totalTokens: Int?
    ) {
        var outputCharacters = 0
        var promptTokens: Int?
        var completionTokens: Int?
        for event in events {
            switch event {
            case .text(let text):
                outputCharacters += text.count
            case .info(let prompt, let completion):
                promptTokens = prompt
                completionTokens = completion
            case .toolCall, .delay:
                break
            }
        }
        return (
            outputCharacters: outputCharacters,
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            totalTokens: totalTokens(promptTokens: promptTokens, completionTokens: completionTokens)
        )
    }

    private func emitTelemetry(_ event: MLXClientTelemetryEvent) async {
        guard let sink = configuration.telemetrySink else { return }
        await sink(event)
    }

    private func emitIgnoredOptionsIfNeeded(_ options: MLXRequestOptions, requestKind: String) async {
        guard !options.ignoredOptionNames.isEmpty else { return }
        await emitTelemetry(
            .requestOptionsIgnored(
                modelID: configuration.modelID,
                requestKind: requestKind,
                names: options.ignoredOptionNames
            )
        )
    }
}

struct MLXClientRequest: Sendable {
    var messages: [ChatRequestBody.Message]
    var tools: [ChatRequestBody.Tool]?
    var options: MLXRequestOptions
}

struct MLXRequestOptions: Sendable, Equatable {
    var maxTokens: Int?
    var temperature: Float?
    var topP: Float?
    var repetitionPenalty: Float?
    var seed: UInt64?
    var stopSequences: [String]
    var ignoredOptionNames: [String]

    static func from(
        body: ChatRequestBody,
        defaultSeed: Int?,
        defaultStop: [String]
    ) -> Self {
        let frequencyPenalty = body.frequencyPenalty ?? 0
        let presencePenalty = body.presencePenalty ?? 0
        let repetitionPenaltyValue = Self.mapRepetitionPenalty(
            frequencyPenalty: frequencyPenalty,
            presencePenalty: presencePenalty
        )
        let effectiveSeed = body.seed ?? defaultSeed
        let effectiveStop = body.stop ?? defaultStop
        return .init(
            maxTokens: body.maxCompletionTokens,
            temperature: body.temperature.map { Float(max(0, $0)) },
            topP: body.topP.map { Float(min(max($0, 0), 1)) },
            repetitionPenalty: repetitionPenaltyValue,
            seed: mapSeed(effectiveSeed),
            stopSequences: normalizedStopSequences(effectiveStop),
            ignoredOptionNames: ignoredOptions(from: body)
        )
    }

    private static func mapRepetitionPenalty(
        frequencyPenalty: Double,
        presencePenalty: Double
    ) -> Float? {
        // OpenAI penalties are in [-2, 2]. MLX repetitionPenalty is most stable in ~[1, 2].
        // We only map positive penalties to avoid turning "encourage repetition" into undefined behavior.
        let positive = max(0, frequencyPenalty, presencePenalty)
        guard positive > 0 else { return nil }
        return Float(1 + min(positive, 1))
    }

    private static func ignoredOptions(from body: ChatRequestBody) -> [String] {
        var names = [String]()
        if body.model != nil { names.append("model") }
        if body.logitBias != nil { names.append("logit_bias") }
        if body.logprobs != nil { names.append("logprobs") }
        if body.n != nil { names.append("n") }
        if body.parallelToolCalls != nil { names.append("parallel_tool_calls") }
        if body.responseFormat != nil { names.append("response_format") }
        if body.store != nil { names.append("store") }
        if body.stream != nil { names.append("stream") }
        if body.streamOptions != nil { names.append("stream_options") }
        if body.toolChoice != nil { names.append("tool_choice") }
        if body.topLogprobs != nil { names.append("top_logprobs") }
        if body.user != nil { names.append("user") }
        return Array(Set(names)).sorted()
    }

    private static func normalizedStopSequences(_ stop: [String]) -> [String] {
        return stop.filter { !$0.isEmpty }
    }

    private static func mapSeed(_ seed: Int?) -> UInt64? {
        guard let seed else { return nil }
        return UInt64(bitPattern: Int64(seed))
    }
}

enum MLXClientEvent: Sendable, Equatable {
    case text(String)
    case toolCall(name: String, argumentsRaw: String)
    case info(prompt: Int, completion: Int)
    case delay(UInt64)

    static func toolCall(name: String, arguments: [String: any Sendable]) -> Self {
        let raw = canonicalJSONString(from: arguments.mapValues { sendableToAny($0) as Any }) ?? "{}"
        return .toolCall(name: name, argumentsRaw: raw)
    }
}

protocol MLXClientBackend: Sendable {
    func ensureLoaded(configuration: MLXClient.Configuration) async throws
    func generate(
        request: MLXClientRequest,
        configuration: MLXClient.Configuration
    ) async throws -> [MLXClientEvent]
    func streamGenerate(
        request: MLXClientRequest,
        configuration: MLXClient.Configuration
    ) async throws -> AsyncThrowingStream<MLXClientEvent, Error>
}

struct MockBackend: MLXClientBackend {
    var nonStreamingEvents: [MLXClientEvent] = []
    var streamingEvents: [MLXClientEvent] = []

    func ensureLoaded(configuration: MLXClient.Configuration) async throws {}

    func generate(
        request: MLXClientRequest,
        configuration: MLXClient.Configuration
    ) async throws -> [MLXClientEvent] {
        nonStreamingEvents
    }

    func streamGenerate(
        request: MLXClientRequest,
        configuration: MLXClient.Configuration
    ) async throws -> AsyncThrowingStream<MLXClientEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                for event in streamingEvents {
                    continuation.yield(event)
                }
                continuation.finish()
            }
        }
    }
}

#if canImport(MLXLMCommon)
import MLXLMCommon
import MLX
import MLXVLM

private actor DefaultMLXBackend: MLXClientBackend {
    private var modelContainer: ModelContainer?

    func ensureLoaded(configuration: MLXClient.Configuration) async throws {
        if modelContainer != nil { return }
        modelContainer = try await loadModelContainer(id: configuration.modelID, revision: configuration.revision)
    }

    func generate(
        request: MLXClientRequest,
        configuration: MLXClient.Configuration
    ) async throws -> [MLXClientEvent] {
        let stream = try await streamGenerate(request: request, configuration: configuration)
        var events = [MLXClientEvent]()
        for try await event in stream {
            events.append(event)
        }
        return events
    }

    func streamGenerate(
        request: MLXClientRequest,
        configuration: MLXClient.Configuration
    ) async throws -> AsyncThrowingStream<MLXClientEvent, Error> {
        guard let modelContainer else {
            throw MLXClientError.modelNotLoaded
        }

        let converted = convertMessages(request.messages)
        let tools = configuration.toolCallEnabled ? convertTools(request.tools) : nil
        let streamInput = prepareStreamingInput(from: converted)
        let generateParameters = makeGenerateParameters(from: request.options)
        let session = ChatSession(
            modelContainer,
            history: streamInput.history,
            generateParameters: generateParameters,
            tools: tools
        )

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    if let seed = request.options.seed {
                        let state = MLXRandom.RandomState(seed: seed)
                        try await withRandomState(state) {
                            try await streamSession(
                                session,
                                prompt: streamInput.prompt,
                                images: streamInput.images,
                                continuation: continuation
                            )
                        }
                    } else {
                        try await streamSession(
                            session,
                            prompt: streamInput.prompt,
                            images: streamInput.images,
                            continuation: continuation
                        )
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

private func streamSession(
    _ session: ChatSession,
    prompt: String,
    images: [UserInput.Image],
    continuation: AsyncThrowingStream<MLXClientEvent, Error>.Continuation
) async throws {
    for try await generation in session.streamDetails(
        to: prompt,
        images: images,
        videos: []
    ) {
        try Task.checkCancellation()
        if let text = generation.chunk, !text.isEmpty {
            continuation.yield(.text(text))
        }
        if let toolCall = generation.toolCall {
            continuation.yield(
                .toolCall(
                    name: toolCall.function.name,
                    argumentsRaw: canonicalJSONString(from: toolCall.function.arguments.mapValues(\.anyValue)) ?? "{}"
                )
            )
        }
        if let info = generation.info {
            continuation.yield(
                .info(
                    prompt: info.promptTokenCount,
                    completion: info.generationTokenCount
                )
            )
        }
    }
}

func prepareStreamingInput(from converted: [Chat.Message]) -> (
    history: [Chat.Message],
    prompt: String,
    images: [UserInput.Image]
) {
    guard let last = converted.last else {
        return (history: [], prompt: "", images: [])
    }
    if last.role == .user {
        return (
            history: Array(converted.dropLast()),
            prompt: last.content,
            images: last.images
        )
    }
    return (
        history: converted,
        prompt: "",
        images: []
    )
}

func convertMessages(_ messages: [ChatRequestBody.Message]) -> [Chat.Message] {
    let mapped = messages.compactMap { message -> Chat.Message? in
        switch message {
        case .assistant(let content, _, _, _):
            return .assistant(content?.stringValue ?? "")
        case .developer(let content, _):
            return .system(content.stringValue)
        case .system(let content, _):
            return .system(content.stringValue)
        case .tool(let content, _):
            return .tool(content.stringValue)
        case .user(let content, _):
            let payload = content.mlxTextAndImages
            return .user(payload.text, images: payload.images)
        }
    }
    return mapped.isEmpty ? [.user("")] : mapped
}

private func convertTools(_ tools: [ChatRequestBody.Tool]?) -> [[String: any Sendable]]? {
    guard let tools else { return nil }
    var result = [[String: any Sendable]]()
    for tool in tools {
        switch tool {
        case let .function(name, description, parameters, _):
            var function = [String: any Sendable]()
            function["name"] = name
            if let description {
                function["description"] = description
            }
            if let parameters {
                function["parameters"] = decodeParameters(parameters) ?? [:]
            }
            result.append([
                "type": "function",
                "function": function,
            ])
        }
    }
    return result.isEmpty ? nil : result
}

private extension ChatRequestBody.Message.MessageContent where SingleType == String, PartsType == [String] {
    var stringValue: String {
        switch self {
        case .text(let value):
            value
        case .parts(let values):
            values.joined(separator: "\n")
        }
    }
}

private extension ChatRequestBody.Message.MessageContent where SingleType == String, PartsType == [ChatRequestBody.Message.ContentPart] {
    var stringValue: String {
        switch self {
        case .text(let value):
            value
        case .parts(let parts):
            parts.compactMap { part -> String? in
                if case .text(let value) = part { return value }
                return nil
            }.joined(separator: "\n")
        }
    }

    var mlxTextAndImages: (text: String, images: [UserInput.Image]) {
        switch self {
        case .text(let value):
            return (text: value, images: [])
        case .parts(let parts):
            var texts = [String]()
            var images = [UserInput.Image]()
            for part in parts {
                switch part {
                case .text(let value):
                    texts.append(value)
                case .imageURL(let url, _):
                    images.append(.url(url))
                }
            }
            return (text: texts.joined(separator: "\n"), images: images)
        }
    }
}

#else
private struct DefaultMLXBackend: MLXClientBackend {
    func ensureLoaded(configuration: MLXClient.Configuration) async throws {
        throw MLXClientError.unsupportedPlatform
    }

    func generate(
        request: MLXClientRequest,
        configuration: MLXClient.Configuration
    ) async throws -> [MLXClientEvent] {
        throw MLXClientError.unsupportedPlatform
    }

    func streamGenerate(
        request: MLXClientRequest,
        configuration: MLXClient.Configuration
    ) async throws -> AsyncThrowingStream<MLXClientEvent, Error> {
        throw MLXClientError.unsupportedPlatform
    }
}
#endif

public enum MLXClientError: Error, LocalizedError {
    case unsupportedPlatform
    case modelNotLoaded
    case requestTimedOut(seconds: TimeInterval)

    public var errorDescription: String? {
        switch self {
        case .unsupportedPlatform:
            return "MLX backend is unavailable on this platform."
        case .modelNotLoaded:
            return "MLX model is not loaded."
        case .requestTimedOut(let seconds):
            return "MLX request timed out after \(seconds) seconds."
        }
    }
}

public enum MLXClientTelemetryEvent: Sendable {
    case requestOptionsIgnored(
        modelID: String,
        requestKind: String,
        names: [String]
    )
    case modelLoaded(
        modelID: String,
        revision: String,
        durationSeconds: TimeInterval
    )
    case respondFinished(
        modelID: String,
        durationSeconds: TimeInterval,
        outputCharacters: Int,
        promptTokens: Int?,
        completionTokens: Int?,
        totalTokens: Int?,
        timedOut: Bool,
        cancelled: Bool
    )
    case streamFinished(
        modelID: String,
        durationSeconds: TimeInterval,
        firstChunkLatencySeconds: TimeInterval?,
        chunkCount: Int,
        outputCharacters: Int,
        promptTokens: Int?,
        completionTokens: Int?,
        totalTokens: Int?,
        timedOut: Bool,
        cancelled: Bool
    )
}

private func telemetryState(for error: Error) -> (timedOut: Bool, cancelled: Bool) {
    if error is CancellationError {
        return (timedOut: false, cancelled: true)
    }
    if case MLXClientError.requestTimedOut = error {
        return (timedOut: true, cancelled: false)
    }
    return (timedOut: false, cancelled: false)
}

private func truncateTextByStopSequences(_ text: String, stopSequences: [String]) -> String {
    guard !stopSequences.isEmpty else { return text }
    var earliest = text.endIndex
    var found = false
    for stop in stopSequences {
        if let range = text.range(of: stop), range.lowerBound < earliest {
            earliest = range.lowerBound
            found = true
        }
    }
    return found ? String(text[..<earliest]) : text
}

private actor StreamingStopBuffer {
    struct Output {
        let prefix: String
        let didStop: Bool
    }

    private var pending = ""
    private let stopSequences: [String]
    private let keepTailLength: Int

    init(stopSequences: [String]) {
        self.stopSequences = stopSequences
        self.keepTailLength = max(0, (stopSequences.map(\.count).max() ?? 0) - 1)
    }

    func consume(_ chunk: String) -> Output {
        pending += chunk
        let truncated = truncateTextByStopSequences(pending, stopSequences: stopSequences)
        if truncated.count < pending.count {
            pending = ""
            return .init(prefix: truncated, didStop: true)
        }
        guard keepTailLength > 0, pending.count > keepTailLength else {
            return .init(prefix: "", didStop: false)
        }
        let cutIndex = pending.index(pending.endIndex, offsetBy: -keepTailLength)
        let prefix = String(pending[..<cutIndex])
        pending = String(pending[cutIndex...])
        return .init(prefix: prefix, didStop: false)
    }

    func flush() -> String {
        defer { pending = "" }
        return pending
    }
}

private func canonicalJSONString(from object: [String: Any]) -> String? {
    guard JSONSerialization.isValidJSONObject(object),
        let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    else { return nil }
    return String(data: data, encoding: .utf8)
}

private func decodeParameters(_ parameters: [String: JSONSchema.JSONValue]) -> [String: any Sendable]? {
    let encoder = JSONEncoder()
    let data = try? encoder.encode(parameters)
    guard let data,
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    return object.mapValues(sendableToAny)
}

private func withTimeout<T: Sendable>(
    _ seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    if seconds <= 0 {
        return try await operation()
    }
    return try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw MLXClientError.requestTimedOut(seconds: seconds)
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

private final class MLXEventIteratorBox: @unchecked Sendable {
    private var iterator: AsyncThrowingStream<MLXClientEvent, Error>.Iterator

    init(_ iterator: AsyncThrowingStream<MLXClientEvent, Error>.Iterator) {
        self.iterator = iterator
    }

    func next() async throws -> MLXClientEvent? {
        try await iterator.next()
    }
}

#if canImport(MLXLMCommon)
private func makeGenerateParameters(from options: MLXRequestOptions) -> GenerateParameters {
    var params = GenerateParameters()
    params.maxTokens = options.maxTokens
    if let temperature = options.temperature {
        params.temperature = temperature
    }
    if let topP = options.topP {
        params.topP = topP
    }
    params.repetitionPenalty = options.repetitionPenalty
    return params
}
#endif

private func sendableToAny(_ value: Any) -> any Sendable {
    switch value {
    case let value as NSNull:
        return value
    case let value as String:
        return value
    case let value as Bool:
        return value
    case let value as Int:
        return value
    case let value as Int8:
        return Int(value)
    case let value as Int16:
        return Int(value)
    case let value as Int32:
        return Int(value)
    case let value as Int64:
        return Int(value)
    case let value as UInt:
        return Int(value)
    case let value as UInt8:
        return Int(value)
    case let value as UInt16:
        return Int(value)
    case let value as UInt32:
        return Int(value)
    case let value as UInt64:
        return Int(value)
    case let value as Float:
        return Double(value)
    case let value as Double:
        return value
    case let array as [Any]:
        return array.map(sendableToAny)
    case let dict as [String: Any]:
        return dict.mapValues(sendableToAny)
    default:
        return String(describing: value)
    }
}
