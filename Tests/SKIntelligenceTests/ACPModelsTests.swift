import XCTest
 import STJSON
@testable import SKIACP

final class ACPModelsTests: XCTestCase {
    func testSessionUpdatePlanRoundTrip() throws {
        let payload = ACPSessionUpdatePayload(
            sessionUpdate: .plan,
            plan: .init(entries: [
                .init(content: "Analyze repository", status: "in_progress", priority: "high"),
                .init(content: "Implement ACP handlers", status: "pending")
            ])
        )
        let params = ACPSessionUpdateParams(sessionId: "sess_1", update: payload)
        let encoded = try ACPCodec.encodeParams(params)
        let decoded = try ACPCodec.decodeParams(encoded, as: ACPSessionUpdateParams.self)
        XCTAssertEqual(decoded.update.sessionUpdate, .plan)
        XCTAssertEqual(decoded.update.plan?.entries.count, 2)
        XCTAssertEqual(decoded.update.plan?.entries.first?.content, "Analyze repository")
    }

    func testSessionUpdateRejectsUnknownKind() throws {
        let json = AnyCodable([
            "sessionId": AnyCodable("sess_2"),
            "update": AnyCodable([
                "sessionUpdate": AnyCodable("unknown_update")
            ])
        ])

        XCTAssertThrowsError(try ACPCodec.decodeParams(json, as: ACPSessionUpdateParams.self))
    }

    func testSessionUpdatePlanRequiresPlanField() throws {
        let json = AnyCodable([
            "sessionId": AnyCodable("sess_plan_missing"),
            "update": AnyCodable([
                "sessionUpdate": AnyCodable("plan")
            ])
        ])

        XCTAssertThrowsError(try ACPCodec.decodeParams(json, as: ACPSessionUpdateParams.self))
    }

    func testSessionUpdateAgentMessageChunkRequiresContentField() throws {
        let json = AnyCodable([
            "sessionId": AnyCodable("sess_msg_missing"),
            "update": AnyCodable([
                "sessionUpdate": AnyCodable("agent_message_chunk")
            ])
        ])

        XCTAssertThrowsError(try ACPCodec.decodeParams(json, as: ACPSessionUpdateParams.self))
    }

    func testPermissionOutcomeRoundTrip() throws {
        let selected = ACPSessionPermissionRequestResult(outcome: .selected(.init(optionId: "allow_once")))
        let selectedValue = try ACPCodec.encodeParams(selected)
        let selectedDecoded = try ACPCodec.decodeParams(selectedValue, as: ACPSessionPermissionRequestResult.self)
        guard case .selected(let selectedOutcome) = selectedDecoded.outcome else {
            return XCTFail("Expected selected outcome")
        }
        XCTAssertEqual(selectedOutcome.optionId, "allow_once")

        let cancelled = ACPSessionPermissionRequestResult(outcome: .cancelled)
        let cancelledValue = try ACPCodec.encodeParams(cancelled)
        let cancelledDecoded = try ACPCodec.decodeParams(cancelledValue, as: ACPSessionPermissionRequestResult.self)
        if case .cancelled = cancelledDecoded.outcome {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected cancelled outcome")
        }
    }

    func testToolCallUpdateRoundTripWithExtendedFields() throws {
        let payload = ACPSessionUpdatePayload(
            sessionUpdate: .toolCallUpdate,
            toolCall: .init(
                toolCallId: "call_1",
                title: "Run command",
                kind: .execute,
                status: .inProgress,
                content: [
                    .content(AnyCodable([
                        "type": AnyCodable("text"),
                        "text": AnyCodable("running")
                    ])),
                    .terminal(.init(terminalId: "term_1")),
                    .diff(.init(path: "README.md", newText: "new", oldText: "old"))
                ],
                locations: [
                    .init(path: "README.md", line: 3)
                ],
                rawInput: AnyCodable(["cmd": AnyCodable("echo hi")]),
                rawOutput: AnyCodable(["stdout": AnyCodable("hi")])
            )
        )
        let params = ACPSessionUpdateParams(sessionId: "sess_tool", update: payload)
        let encoded = try ACPCodec.encodeParams(params)
        let decoded = try ACPCodec.decodeParams(encoded, as: ACPSessionUpdateParams.self)
        let toolCall = try XCTUnwrap(decoded.update.toolCall)
        XCTAssertEqual(toolCall.toolCallId, "call_1")
        XCTAssertEqual(toolCall.title, "Run command")
        XCTAssertEqual(toolCall.kind, .execute)
        XCTAssertEqual(toolCall.status, .inProgress)
        XCTAssertEqual(toolCall.locations?.first?.path, "README.md")
        XCTAssertEqual(toolCall.locations?.first?.line, 3)
        let inputObject = try XCTUnwrap(toolCall.rawInput?.decode(to: [String: AnyCodable].self))
        let outputObject = try XCTUnwrap(toolCall.rawOutput?.decode(to: [String: AnyCodable].self))
        XCTAssertEqual(inputObject["cmd"]?.value as? String, "echo hi")
        XCTAssertEqual(outputObject["stdout"]?.value as? String, "hi")
        XCTAssertEqual(toolCall.content?.count, 3)
    }

    func testToolCallUpdateSupportsPartialPayload() throws {
        let json = AnyCodable([
            "sessionId": AnyCodable("sess_partial"),
            "update": AnyCodable([
                "sessionUpdate": AnyCodable("tool_call_update"),
                "toolCall": AnyCodable([
                    "toolCallId": AnyCodable("call_2"),
                    "status": AnyCodable("completed")
                ])
            ])
        ])
        let decoded = try ACPCodec.decodeParams(json, as: ACPSessionUpdateParams.self)
        let toolCall = try XCTUnwrap(decoded.update.toolCall)
        XCTAssertEqual(toolCall.toolCallId, "call_2")
        XCTAssertEqual(toolCall.status, .completed)
        XCTAssertNil(toolCall.title)
        XCTAssertNil(toolCall.content)
    }

    func testPromptContentImageRoundTrip() throws {
        let params = ACPSessionPromptParams(
            sessionId: "sess_img",
            prompt: [
                .image(data: "ZmFrZQ==", mimeType: "image/png", uri: "file:///tmp/demo.png")
            ]
        )
        let encoded = try ACPCodec.encodeParams(params)
        let decoded = try ACPCodec.decodeParams(encoded, as: ACPSessionPromptParams.self)
        XCTAssertEqual(decoded.prompt.count, 1)
        XCTAssertEqual(decoded.prompt.first?.type, "image")
        XCTAssertEqual(decoded.prompt.first?.mimeType, "image/png")
        XCTAssertEqual(decoded.prompt.first?.data, "ZmFrZQ==")
        XCTAssertEqual(decoded.prompt.first?.uri, "file:///tmp/demo.png")
    }

    func testSessionUpdateContentResourceLinkRoundTrip() throws {
        let params = ACPSessionUpdateParams(
            sessionId: "sess_link",
            update: .init(
                sessionUpdate: .agentMessageChunk,
                content: .resourceLink(
                    name: "README",
                    uri: "file:///repo/README.md",
                    description: "project readme",
                    mimeType: "text/markdown"
                )
            )
        )
        let encoded = try ACPCodec.encodeParams(params)
        let decoded = try ACPCodec.decodeParams(encoded, as: ACPSessionUpdateParams.self)
        let content = try XCTUnwrap(decoded.update.content)
        XCTAssertEqual(content.type, "resource_link")
        XCTAssertEqual(content.name, "README")
        XCTAssertEqual(content.uri, "file:///repo/README.md")
        XCTAssertEqual(content.description, "project readme")
        XCTAssertEqual(content.mimeType, "text/markdown")
    }

    func testSessionUpdateContentUnknownTypePreserved() throws {
        let json = AnyCodable([
            "sessionId": AnyCodable("sess_unknown"),
            "update": AnyCodable([
                "sessionUpdate": AnyCodable("agent_message_chunk"),
                "content": AnyCodable([
                    "type": AnyCodable("custom_block"),
                    "foo": AnyCodable("bar"),
                    "answer": AnyCodable(Double(42))
                ])
            ])
        ])

        let decoded = try ACPCodec.decodeParams(json, as: ACPSessionUpdateParams.self)
        let content = try XCTUnwrap(decoded.update.content)
        XCTAssertEqual(content.type, "custom_block")

        let reencoded = try ACPCodec.encodeParams(decoded)
        let root = try XCTUnwrap(try? reencoded.decode(to: [String: AnyCodable].self))
        let update = try XCTUnwrap(try? root["update"]?.decode(to: [String: AnyCodable].self))
        let contentObj = try XCTUnwrap(try? update["content"]?.decode(to: [String: AnyCodable].self))
        if contentObj.isEmpty {
            return XCTFail("Missing re-encoded content payload")
        }
        XCTAssertEqual(contentObj["foo"], AnyCodable("bar"))
        let answer = numericDouble(from: contentObj["answer"]?.value)
        XCTAssertEqual(answer, 42)
    }

    func testSessionSetModelParamsRoundTrip() throws {
        let params = ACPSessionSetModelParams(sessionId: "sess_model", modelId: "gpt-5")
        let encoded = try ACPCodec.encodeParams(params)
        let decoded = try ACPCodec.decodeParams(encoded, as: ACPSessionSetModelParams.self)
        XCTAssertEqual(decoded.sessionId, "sess_model")
        XCTAssertEqual(decoded.modelId, "gpt-5")
    }

    func testBooleanConfigOptionDecodesFromBoolCurrentValue() throws {
        let json = AnyCodable([
            "type": AnyCodable("boolean"),
            "id": AnyCodable("streaming"),
            "name": AnyCodable("Streaming"),
            "currentValue": AnyCodable(true)
        ])
        let decoded = try ACPCodec.decodeParams(json, as: ACPSessionConfigOption.self)
        XCTAssertEqual(decoded.type, .boolean)
        XCTAssertEqual(decoded.currentValue, "true")

        let reencoded = try ACPCodec.encodeParams(decoded)
        guard let root = try? reencoded.decode(to: [String: AnyCodable].self) else {
            return XCTFail("Expected object")
        }
        XCTAssertEqual(root["type"], AnyCodable("boolean"))
        XCTAssertEqual(root["currentValue"], AnyCodable(true))
    }

    private func numericDouble(from raw: Any?) -> Double? {
        switch raw {
        case let value as Double: return value
        case let value as Float: return Double(value)
        case let value as Int: return Double(value)
        case let value as Int8: return Double(value)
        case let value as Int16: return Double(value)
        case let value as Int32: return Double(value)
        case let value as Int64: return Double(value)
        case let value as UInt: return Double(value)
        case let value as UInt8: return Double(value)
        case let value as UInt16: return Double(value)
        case let value as UInt32: return Double(value)
        case let value as UInt64: return Double(value)
        default: return nil
        }
    }

    func testCancelRequestParamsRoundTrip() throws {
        let params = ACPCancelRequestParams(requestId: .int(123))
        let encoded = try ACPCodec.encodeParams(params)
        let decoded = try ACPCodec.decodeParams(encoded, as: ACPCancelRequestParams.self)
        XCTAssertEqual(decoded.requestId, .int(123))
    }

    func testLogoutParamsRoundTrip() throws {
        let encoded = try ACPCodec.encodeParams(ACPLogoutParams())
        _ = try ACPCodec.decodeParams(encoded, as: ACPLogoutParams.self)
    }

    func testSessionNewResultModelsRoundTrip() throws {
        let result = ACPSessionNewResult(
            sessionId: "sess_models",
            modes: nil,
            models: .init(
                currentModelId: "gpt-5",
                availableModels: [
                    .init(modelId: "gpt-5", name: "GPT-5"),
                    .init(modelId: "gpt-5-mini", name: "GPT-5 Mini")
                ]
            ),
            configOptions: nil
        )
        let encoded = try ACPCodec.encodeParams(result)
        let decoded = try ACPCodec.decodeParams(encoded, as: ACPSessionNewResult.self)
        XCTAssertEqual(decoded.models?.currentModelId, "gpt-5")
        XCTAssertEqual(decoded.models?.availableModels.count, 2)
        XCTAssertEqual(decoded.models?.availableModels.last?.modelId, "gpt-5-mini")
    }

    func testSessionListResultRoundTrip() throws {
        let result = ACPSessionListResult(
            sessions: [
                .init(
                    sessionId: "sess_1",
                    cwd: "/tmp/a",
                    title: "A",
                    updatedAt: "2026-02-12T10:00:00Z",
                    parentSessionId: nil,
                    messageCount: 2
                ),
                .init(sessionId: "sess_2", cwd: "/tmp/b")
            ],
            nextCursor: "cursor_2"
        )
        let encoded = try ACPCodec.encodeParams(result)
        let decoded = try ACPCodec.decodeParams(encoded, as: ACPSessionListResult.self)
        XCTAssertEqual(decoded.sessions.count, 2)
        XCTAssertEqual(decoded.sessions.first?.sessionId, "sess_1")
        XCTAssertEqual(decoded.sessions.first?.messageCount, 2)
        XCTAssertEqual(decoded.nextCursor, "cursor_2")
    }

    func testSessionExportRoundTrip() throws {
        let params = ACPSessionExportParams(sessionId: "sess_export", format: .jsonl)
        let encodedParams = try ACPCodec.encodeParams(params)
        let decodedParams = try ACPCodec.decodeParams(encodedParams, as: ACPSessionExportParams.self)
        XCTAssertEqual(decodedParams.sessionId, "sess_export")
        XCTAssertEqual(decodedParams.format, .jsonl)

        let result = ACPSessionExportResult(
            sessionId: "sess_export",
            format: .jsonl,
            mimeType: "application/x-ndjson",
            content: "{\"type\":\"session\"}\n{\"message\":{}}\n"
        )
        let encodedResult = try ACPCodec.encodeParams(result)
        let decodedResult = try ACPCodec.decodeParams(encodedResult, as: ACPSessionExportResult.self)
        XCTAssertEqual(decodedResult.sessionId, "sess_export")
        XCTAssertEqual(decodedResult.format, .jsonl)
        XCTAssertEqual(decodedResult.mimeType, "application/x-ndjson")
        XCTAssertTrue(decodedResult.content.contains("\"type\":\"session\""))
    }

    func testSessionDeleteParamsRoundTrip() throws {
        let params = ACPSessionDeleteParams(sessionId: "sess_delete")
        let encoded = try ACPCodec.encodeParams(params)
        let decoded = try ACPCodec.decodeParams(encoded, as: ACPSessionDeleteParams.self)
        XCTAssertEqual(decoded.sessionId, "sess_delete")
    }

    func testSessionInfoUpdateRoundTrip() throws {
        let params = ACPSessionUpdateParams(
            sessionId: "sess_info",
            update: .init(
                sessionUpdate: .sessionInfoUpdate,
                sessionInfoUpdate: .init(title: "Auth Debug", updatedAt: "2026-02-12T19:10:00Z")
            )
        )
        let encoded = try ACPCodec.encodeParams(params)
        let decoded = try ACPCodec.decodeParams(encoded, as: ACPSessionUpdateParams.self)
        XCTAssertEqual(decoded.update.sessionUpdate, .sessionInfoUpdate)
        XCTAssertEqual(decoded.update.sessionInfoUpdate?.title, "Auth Debug")
        XCTAssertEqual(decoded.update.sessionInfoUpdate?.updatedAt, "2026-02-12T19:10:00Z")
    }

    func testExecutionStateUpdateRoundTrip() throws {
        let params = ACPSessionUpdateParams(
            sessionId: "sess_exec",
            update: .init(
                sessionUpdate: .executionStateUpdate,
                executionStateUpdate: .init(state: .running, attempt: 1, message: "prompt started")
            )
        )
        let encoded = try ACPCodec.encodeParams(params)
        let decoded = try ACPCodec.decodeParams(encoded, as: ACPSessionUpdateParams.self)
        XCTAssertEqual(decoded.update.sessionUpdate, .executionStateUpdate)
        XCTAssertEqual(decoded.update.executionStateUpdate?.state, .running)
        XCTAssertEqual(decoded.update.executionStateUpdate?.attempt, 1)
        XCTAssertEqual(decoded.update.executionStateUpdate?.message, "prompt started")
    }

    func testRetryUpdateRoundTrip() throws {
        let params = ACPSessionUpdateParams(
            sessionId: "sess_retry",
            update: .init(
                sessionUpdate: .retryUpdate,
                retryUpdate: .init(attempt: 1, maxAttempts: 2, reason: "transient")
            )
        )
        let encoded = try ACPCodec.encodeParams(params)
        let decoded = try ACPCodec.decodeParams(encoded, as: ACPSessionUpdateParams.self)
        XCTAssertEqual(decoded.update.sessionUpdate, .retryUpdate)
        XCTAssertEqual(decoded.update.retryUpdate?.attempt, 1)
        XCTAssertEqual(decoded.update.retryUpdate?.maxAttempts, 2)
        XCTAssertEqual(decoded.update.retryUpdate?.reason, "transient")
    }
}
