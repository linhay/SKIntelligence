import Foundation
import HTTPTypes
import XCTest

@testable import SKIMLXClient
@testable import SKIntelligence

final class MLXClientTests: XCTestCase {
    func testRespondEmitsTelemetryEvents() async throws {
        let telemetry = MLXTelemetryBox()
        let backend = MockBackend(
            nonStreamingEvents: [.text("hello from mlx"), .info(prompt: 10, completion: 6)]
        )
        let client = MLXClient(
            configuration: .init(
                modelID: "mock/model",
                telemetrySink: { event in await telemetry.append(event) }
            ),
            backend: backend
        )

        _ = try await client.respond(ChatRequestBody(messages: [.user(content: .text("hi"))]))
        let events = await telemetry.snapshot()

        XCTAssertTrue(
            events.contains { event in
                if case .modelLoaded(let modelID, _, _) = event {
                    return modelID == "mock/model"
                }
                return false
            }
        )
        XCTAssertTrue(
            events.contains { event in
                if case .respondFinished(_, _, let outputCharacters, let prompt, let completion, let total, let timedOut, let cancelled) = event {
                    return outputCharacters > 0
                        && prompt == 10
                        && completion == 6
                        && total == 16
                        && !timedOut
                        && !cancelled
                }
                return false
            }
        )
    }

    func testStreamingTimeoutEmitsTimedOutTelemetry() async throws {
        let telemetry = MLXTelemetryBox()
        let backend = HangingBackend(
            generateDelayNanos: 0,
            streamDelayNanos: 200_000_000
        )
        let client = MLXClient(
            configuration: .init(
                modelID: "mock/model",
                requestTimeout: 0.01,
                telemetrySink: { event in await telemetry.append(event) }
            ),
            backend: backend
        )

        let stream = try await client.streamingRespond(
            ChatRequestBody(messages: [.user(content: .text("hi"))])
        )

        do {
            for try await _ in stream {}
            XCTFail("expected timeout")
        } catch {
            // expected timeout path
        }

        let events = await telemetry.snapshot()
        XCTAssertTrue(
            events.contains { event in
                if case .streamFinished(_, _, _, _, _, _, _, _, let timedOut, let cancelled) = event {
                    return timedOut && !cancelled
                }
                return false
            }
        )
    }

    func testRespondMapsSeedAndStopWithoutIgnoredOptionsTelemetry() async throws {
        let telemetry = MLXTelemetryBox()
        let backend = CapturingBackend(nonStreamingEvents: [.text("ok")])
        let client = MLXClient(
            configuration: .init(
                modelID: "mock/model",
                telemetrySink: { event in await telemetry.append(event) }
            ),
            backend: backend
        )

        _ = try await client.respond(
            ChatRequestBody(
                messages: [.user(content: .text("hi"))],
                seed: 42,
                stop: ["DONE"]
            )
        )

        let request = await backend.lastRequest
        XCTAssertEqual(request?.options.seed, 42)
        XCTAssertEqual(request?.options.stopSequences, ["DONE"])

        let events = await telemetry.snapshot()
        XCTAssertFalse(
            events.contains { event in
                if case .requestOptionsIgnored = event { return true }
                return false
            }
        )
    }

    func testRespondEmitsIgnoredOptionsTelemetryForUnsupportedFields() async throws {
        let telemetry = MLXTelemetryBox()
        let backend = CapturingBackend(nonStreamingEvents: [.text("ok")])
        let client = MLXClient(
            configuration: .init(
                modelID: "mock/model",
                telemetrySink: { event in await telemetry.append(event) }
            ),
            backend: backend
        )

        var body = ChatRequestBody(
            messages: [.user(content: .text("hi"))],
            logitBias: ["42": 1],
            logprobs: true,
            n: 2,
            parallelToolCalls: false,
            responseFormat: .jsonObject,
            store: true,
            stream: true,
            streamOptions: .init(includeUsage: true),
            toolChoice: .required,
            topLogprobs: 2,
            user: "tester"
        )
        body.model = "override-me"

        _ = try await client.respond(body)
        let events = await telemetry.snapshot()

        let ignoredNames = events.compactMap { event -> [String]? in
            guard case .requestOptionsIgnored(_, let requestKind, let names) = event else { return nil }
            return requestKind == "respond" ? names : nil
        }.first

        XCTAssertEqual(
            ignoredNames,
            [
                "logit_bias",
                "logprobs",
                "model",
                "n",
                "parallel_tool_calls",
                "response_format",
                "store",
                "stream",
                "stream_options",
                "tool_choice",
                "top_logprobs",
                "user",
            ]
        )
    }

    func testStreamingRespondEmitsIgnoredOptionsTelemetryForUnsupportedFields() async throws {
        let telemetry = MLXTelemetryBox()
        let backend = MockBackend(streamingEvents: [.text("ok")])
        let client = MLXClient(
            configuration: .init(
                modelID: "mock/model",
                telemetrySink: { event in await telemetry.append(event) }
            ),
            backend: backend
        )

        var body = ChatRequestBody(
            messages: [.user(content: .text("hi"))],
            logitBias: ["42": 1],
            responseFormat: .jsonObject,
            toolChoice: .required,
            user: "tester"
        )
        body.model = "override-me"

        let stream = try await client.streamingRespond(body)
        for try await _ in stream {}

        let events = await telemetry.snapshot()
        let ignoredNames = events.compactMap { event -> [String]? in
            guard case .requestOptionsIgnored(_, let requestKind, let names) = event else { return nil }
            return requestKind == "stream" ? names : nil
        }.first

        XCTAssertEqual(
            ignoredNames,
            [
                "logit_bias",
                "model",
                "response_format",
                "tool_choice",
                "user",
            ]
        )
    }

    func testRespondUsesConfigurationDefaultSeedAndStopWhenRequestOmitsThem() async throws {
        let backend = CapturingBackend(nonStreamingEvents: [.text("hello DONE world")])
        let client = MLXClient(
            configuration: .init(
                modelID: "mock/model",
                defaultSeed: 7,
                defaultStop: ["DONE"]
            ),
            backend: backend
        )

        let response = try await client.respond(
            ChatRequestBody(messages: [.user(content: .text("hi"))])
        )
        let request = await backend.lastRequest

        XCTAssertEqual(request?.options.seed, 7)
        XCTAssertEqual(request?.options.stopSequences, ["DONE"])
        XCTAssertEqual(response.content.choices.first?.message.content, "hello ")
    }

    func testRespondRequestSeedAndStopOverrideConfigurationDefaults() async throws {
        let backend = CapturingBackend(nonStreamingEvents: [.text("hello STOP world")])
        let client = MLXClient(
            configuration: .init(
                modelID: "mock/model",
                defaultSeed: 7,
                defaultStop: ["DONE"]
            ),
            backend: backend
        )

        _ = try await client.respond(
            ChatRequestBody(
                messages: [.user(content: .text("hi"))],
                seed: 11,
                stop: ["STOP"]
            )
        )
        let request = await backend.lastRequest

        XCTAssertEqual(request?.options.seed, 11)
        XCTAssertEqual(request?.options.stopSequences, ["STOP"])
    }

    func testRespondPreservesExactStopSequencesIncludingWhitespace() async throws {
        let backend = CapturingBackend(nonStreamingEvents: [.text("ok")])
        let client = MLXClient(
            configuration: .init(modelID: "mock/model"),
            backend: backend
        )
        let stop = ["\n\n", " END", "END ", "\tSTOP"]

        _ = try await client.respond(
            ChatRequestBody(
                messages: [.user(content: .text("hi"))],
                stop: stop
            )
        )

        let request = await backend.lastRequest
        XCTAssertEqual(request?.options.stopSequences, stop)
    }

    func testRespondAppliesStopSequenceToText() async throws {
        let backend = MockBackend(
            nonStreamingEvents: [.text("hello DONE world"), .info(prompt: 3, completion: 4)]
        )
        let client = MLXClient(
            configuration: .init(modelID: "mock/model"),
            backend: backend
        )

        let response = try await client.respond(
            ChatRequestBody(
                messages: [.user(content: .text("hi"))],
                stop: ["DONE"]
            )
        )
        XCTAssertEqual(response.content.choices.first?.message.content, "hello ")
    }

    func testStreamingRespondAppliesStopSequenceAcrossChunkBoundary() async throws {
        let backend = MockBackend(
            streamingEvents: [.text("ab"), .text("cd"), .text("ef"), .text("gh")]
        )
        let client = MLXClient(
            configuration: .init(modelID: "mock/model"),
            backend: backend
        )

        let stream = try await client.streamingRespond(
            ChatRequestBody(
                messages: [.user(content: .text("hi"))],
                stop: ["cde"]
            )
        )

        var text = ""
        for try await chunk in stream {
            text += chunk.text ?? ""
        }
        XCTAssertEqual(text, "ab")
    }

    func testRespondMapsSamplingOptionsToMLXRequest() async throws {
        let backend = CapturingBackend(nonStreamingEvents: [.text("ok")])
        let client = MLXClient(
            configuration: .init(modelID: "mock/model", toolCallEnabled: true),
            backend: backend
        )

        _ = try await client.respond(
            ChatRequestBody(
                messages: [.user(content: .text("hi"))],
                frequencyPenalty: 0.3,
                maxCompletionTokens: 128,
                temperature: 0.2,
                tools: [.function(name: "echo", description: nil, parameters: [:], strict: true)],
                topP: 0.8
            )
        )

        let request = await backend.lastRequest
        XCTAssertEqual(request?.options.maxTokens, 128)
        XCTAssertEqual(request?.options.temperature, 0.2)
        XCTAssertEqual(request?.options.topP, 0.8)
        let repetitionPenalty = try XCTUnwrap(request?.options.repetitionPenalty)
        XCTAssertEqual(repetitionPenalty, Float(1.3), accuracy: 0.0001)
        XCTAssertEqual(request?.tools?.count, 1)
    }

    func testRespondMapsPresencePenaltyToRepetitionPenaltyWithUpperBound() async throws {
        let backend = CapturingBackend(nonStreamingEvents: [.text("ok")])
        let client = MLXClient(
            configuration: .init(modelID: "mock/model"),
            backend: backend
        )

        _ = try await client.respond(
            ChatRequestBody(
                messages: [.user(content: .text("hi"))],
                presencePenalty: 2
            )
        )

        let request = await backend.lastRequest
        let repetitionPenalty = try XCTUnwrap(request?.options.repetitionPenalty)
        XCTAssertEqual(repetitionPenalty, Float(2.0), accuracy: 0.0001)
    }

    func testRespondDoesNotMapNegativePenaltyToRepetitionPenalty() async throws {
        let backend = CapturingBackend(nonStreamingEvents: [.text("ok")])
        let client = MLXClient(
            configuration: .init(modelID: "mock/model"),
            backend: backend
        )

        _ = try await client.respond(
            ChatRequestBody(
                messages: [.user(content: .text("hi"))],
                frequencyPenalty: -1.5,
                presencePenalty: -0.5
            )
        )

        let request = await backend.lastRequest
        XCTAssertNil(request?.options.repetitionPenalty)
    }

    func testRespondDropsToolsWhenToolCallDisabled() async throws {
        let backend = CapturingBackend(nonStreamingEvents: [.text("ok")])
        let client = MLXClient(
            configuration: .init(modelID: "mock/model", toolCallEnabled: false),
            backend: backend
        )

        _ = try await client.respond(
            ChatRequestBody(
                messages: [.user(content: .text("hi"))],
                tools: [.function(name: "echo", description: nil, parameters: [:], strict: true)]
            )
        )

        let request = await backend.lastRequest
        XCTAssertNil(request?.tools)
    }

    func testRespondMapsTextToChatResponseBody() async throws {
        let backend = MockBackend(
            nonStreamingEvents: [.text("hello from mlx"), .info(prompt: 10, completion: 6)]
        )
        let client = MLXClient(
            configuration: .init(modelID: "mock/model"),
            backend: backend
        )

        let response = try await client.respond(
            ChatRequestBody(messages: [.user(content: .text("hi"))])
        )

        XCTAssertEqual(response.httpResponse.status.code, 200)
        XCTAssertEqual(response.content.choices.first?.message.role, "assistant")
        XCTAssertEqual(response.content.choices.first?.message.content, "hello from mlx")
        XCTAssertEqual(response.content.choices.first?.finishReason, "stop")
        XCTAssertEqual(response.content.usage?.promptTokens, 10)
        XCTAssertEqual(response.content.usage?.completionTokens, 6)
        XCTAssertEqual(response.content.usage?.totalTokens, 16)
    }

    func testRespondMapsToolCallToChatResponseBodyToolCalls() async throws {
        let backend = MockBackend(
            nonStreamingEvents: [
                .toolCall(name: "add", arguments: ["a": 2, "b": 3])
            ]
        )
        let client = MLXClient(
            configuration: .init(modelID: "mock/model", toolCallEnabled: true),
            backend: backend
        )

        let response = try await client.respond(
            ChatRequestBody(messages: [.user(content: .text("calc"))])
        )

        let toolCall = try XCTUnwrap(response.content.choices.first?.message.toolCalls?.first)
        XCTAssertEqual(toolCall.function.name, "add")
        XCTAssertEqual(toolCall.function.arguments?["a"] as? Int, 2)
        XCTAssertEqual(toolCall.function.arguments?["b"] as? Int, 3)
        XCTAssertEqual(toolCall.function.argumentsRaw, #"{"a":2,"b":3}"#)
    }

    func testStreamingRespondEmitsTextChunks() async throws {
        let backend = MockBackend(
            streamingEvents: [.text("hello"), .text(" "), .text("world"), .info(prompt: 3, completion: 4)]
        )
        let client = MLXClient(
            configuration: .init(modelID: "mock/model"),
            backend: backend
        )

        let stream = try await client.streamingRespond(
            ChatRequestBody(messages: [.user(content: .text("say hi"))])
        )

        var text = ""
        var usage: ChatUsage?
        for try await chunk in stream {
            text += chunk.text ?? ""
            usage = chunk.usage ?? usage
        }

        XCTAssertEqual(text, "hello world")
        XCTAssertEqual(usage?.promptTokens, 3)
        XCTAssertEqual(usage?.completionTokens, 4)
        XCTAssertEqual(usage?.totalTokens, 7)
    }

    func testStreamingRespondEmitsToolCallDeltas() async throws {
        let backend = MockBackend(
            streamingEvents: [.toolCall(name: "weather", arguments: ["location": "Shanghai"])]
        )
        let client = MLXClient(
            configuration: .init(modelID: "mock/model", toolCallEnabled: true),
            backend: backend
        )

        let stream = try await client.streamingRespond(
            ChatRequestBody(messages: [.user(content: .text("weather"))])
        )

        var deltas = [ToolCallDelta]()
        for try await chunk in stream {
            deltas.append(contentsOf: chunk.toolCallDeltas ?? [])
        }

        let delta = try XCTUnwrap(deltas.first)
        XCTAssertEqual(delta.index, 0)
        XCTAssertEqual(delta.function?.name, "weather")
        XCTAssertEqual(delta.function?.arguments, #"{"location":"Shanghai"}"#)
    }

    func testStreamingRespondEmitsDistinctIndicesForMultipleToolCalls() async throws {
        let backend = MockBackend(
            streamingEvents: [
                .toolCall(name: "weather", arguments: ["location": "Shanghai"]),
                .toolCall(name: "news", arguments: ["topic": "AI"]),
            ]
        )
        let client = MLXClient(
            configuration: .init(modelID: "mock/model", toolCallEnabled: true),
            backend: backend
        )

        let stream = try await client.streamingRespond(
            ChatRequestBody(messages: [.user(content: .text("weather and news"))])
        )

        var deltas = [ToolCallDelta]()
        for try await chunk in stream {
            deltas.append(contentsOf: chunk.toolCallDeltas ?? [])
        }

        XCTAssertEqual(deltas.count, 2)
        XCTAssertEqual(deltas[0].index, 0)
        XCTAssertEqual(deltas[0].function?.name, "weather")
        XCTAssertEqual(deltas[1].index, 1)
        XCTAssertEqual(deltas[1].function?.name, "news")
    }

    func testStreamingRespondPropagatesCancellation() async throws {
        let backend = MockBackend(
            streamingEvents: [.delay(200_000_000), .text("should not happen")]
        )
        let client = MLXClient(
            configuration: .init(modelID: "mock/model"),
            backend: backend
        )

        let stream = try await client.streamingRespond(
            ChatRequestBody(messages: [.user(content: .text("cancel me"))])
        )

        let task = Task {
            for try await _ in stream {
                XCTFail("stream should be cancelled before yielding")
            }
            try Task.checkCancellation()
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testRespondTimesOutWhenBackendGenerateHangs() async throws {
        let backend = HangingBackend(
            generateDelayNanos: 200_000_000,
            streamDelayNanos: 0
        )
        let client = MLXClient(
            configuration: .init(modelID: "mock/model", requestTimeout: 0.01),
            backend: backend
        )

        do {
            _ = try await client.respond(ChatRequestBody(messages: [.user(content: .text("hi"))]))
            XCTFail("expected timeout")
        } catch let error as MLXClientError {
            guard case .requestTimedOut = error else {
                return XCTFail("unexpected mlx error: \(error)")
            }
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testStreamingRespondTimesOutWhenNoChunkArrivesInTime() async throws {
        let backend = HangingBackend(
            generateDelayNanos: 0,
            streamDelayNanos: 200_000_000
        )
        let client = MLXClient(
            configuration: .init(modelID: "mock/model", requestTimeout: 0.01),
            backend: backend
        )

        let stream = try await client.streamingRespond(
            ChatRequestBody(messages: [.user(content: .text("hi"))])
        )

        do {
            for try await _ in stream {
                XCTFail("expected timeout before receiving any chunk")
            }
            XCTFail("expected timeout")
        } catch let error as MLXClientError {
            guard case .requestTimedOut = error else {
                return XCTFail("unexpected mlx error: \(error)")
            }
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

#if canImport(MLXLMCommon)
    func testConvertMessagesMapsUserImagePartsToMLXImages() throws {
        let imageA = URL(string: "https://example.com/a.png")!
        let imageB = URL(string: "https://example.com/b.png")!
        let messages: [ChatRequestBody.Message] = [
            .user(
                content: .parts([
                    .text("describe this"),
                    .imageURL(imageA),
                    .imageURL(imageB),
                ])
            )
        ]

        let converted = convertMessages(messages)
        XCTAssertEqual(converted.count, 1)
        XCTAssertEqual(converted[0].content, "describe this")
        XCTAssertEqual(converted[0].images.count, 2)

        guard case .url(let mappedA) = converted[0].images[0] else {
            return XCTFail("expected first image to map as .url")
        }
        XCTAssertEqual(mappedA, imageA)

        guard case .url(let mappedB) = converted[0].images[1] else {
            return XCTFail("expected second image to map as .url")
        }
        XCTAssertEqual(mappedB, imageB)
    }

    func testPrepareStreamingInputPreservesLatestUserImages() throws {
        let imageURL = URL(string: "https://example.com/cat.png")!
        let messages: [ChatRequestBody.Message] = [
            .system(content: .text("You are helpful.")),
            .user(
                content: .parts([
                    .text("describe image"),
                    .imageURL(imageURL),
                ])
            ),
        ]

        let converted = convertMessages(messages)
        let input = prepareStreamingInput(from: converted)

        XCTAssertEqual(input.history.count, 1)
        XCTAssertEqual(input.prompt, "describe image")
        XCTAssertEqual(input.images.count, 1)
        guard case .url(let mappedURL) = input.images[0] else {
            return XCTFail("expected latest user image to map as .url")
        }
        XCTAssertEqual(mappedURL, imageURL)
    }

    func testPrepareStreamingInputKeepsNonUserTailInHistory() throws {
        let messages: [ChatRequestBody.Message] = [
            .system(content: .text("You are helpful.")),
            .user(content: .text("Need weather and news")),
            .assistant(content: .text("Calling tools")),
            .tool(content: .text("{\"weather\":\"sunny\"}"), toolCallID: "call_weather"),
        ]

        let converted = convertMessages(messages)
        let input = prepareStreamingInput(from: converted)

        XCTAssertEqual(input.history.count, converted.count)
        XCTAssertEqual(input.history.last?.role, .tool)
        XCTAssertEqual(input.prompt, "")
        XCTAssertTrue(input.images.isEmpty)
    }
#endif
}

private actor CapturingBackend: MLXClientBackend {
    private(set) var lastRequest: MLXClientRequest?
    private let nonStreamingEvents: [MLXClientEvent]

    init(nonStreamingEvents: [MLXClientEvent]) {
        self.nonStreamingEvents = nonStreamingEvents
    }

    func ensureLoaded(configuration: MLXClient.Configuration) async throws {}

    func generate(
        request: MLXClientRequest,
        configuration: MLXClient.Configuration
    ) async throws -> [MLXClientEvent] {
        lastRequest = request
        return nonStreamingEvents
    }

    func streamGenerate(
        request: MLXClientRequest,
        configuration: MLXClient.Configuration
    ) async throws -> AsyncThrowingStream<MLXClientEvent, Error> {
        lastRequest = request
        return AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

private actor HangingBackend: MLXClientBackend {
    private let generateDelayNanos: UInt64
    private let streamDelayNanos: UInt64

    init(generateDelayNanos: UInt64, streamDelayNanos: UInt64) {
        self.generateDelayNanos = generateDelayNanos
        self.streamDelayNanos = streamDelayNanos
    }

    func ensureLoaded(configuration: MLXClient.Configuration) async throws {}

    func generate(
        request: MLXClientRequest,
        configuration: MLXClient.Configuration
    ) async throws -> [MLXClientEvent] {
        if generateDelayNanos > 0 {
            try await Task.sleep(nanoseconds: generateDelayNanos)
        }
        return [.text("late")]
    }

    func streamGenerate(
        request: MLXClientRequest,
        configuration: MLXClient.Configuration
    ) async throws -> AsyncThrowingStream<MLXClientEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                if streamDelayNanos > 0 {
                    try? await Task.sleep(nanoseconds: streamDelayNanos)
                }
                continuation.yield(.text("late"))
                continuation.finish()
            }
        }
    }
}

private actor MLXTelemetryBox {
    private var values: [MLXClientTelemetryEvent] = []

    func append(_ value: MLXClientTelemetryEvent) {
        values.append(value)
    }

    func snapshot() -> [MLXClientTelemetryEvent] {
        values
    }
}
