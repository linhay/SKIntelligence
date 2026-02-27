import XCTest
import HTTPTypes
@testable import SKIACP
@testable import SKIACPAgent
@testable import SKIJSONRPC
@testable import SKIntelligence

final class ACPAgentServiceTests: XCTestCase {
    func testInitializeAndSessionPromptWithAgentSessionFactory() async throws {
        let notifications = NotificationBox()

        let service = ACPAgentService(
            agentSessionFactory: { SKIAgentSession(client: EchoTestClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(loadSession: true),
            notificationSink: { n in await notifications.append(n) }
        )

        let initReq = JSONRPCRequest(
            id: .int(101),
            method: ACPMethods.initialize,
            params: try ACPCodec.encodeParams(ACPInitializeParams(protocolVersion: 1))
        )
        let initResp = await service.handle(initReq)
        XCTAssertNil(initResp.error)

        let newReq = JSONRPCRequest(
            id: .int(102),
            method: ACPMethods.sessionNew,
            params: try ACPCodec.encodeParams(ACPSessionNewParams(cwd: "/tmp"))
        )
        let newResp = await service.handle(newReq)
        let newResult = try ACPCodec.decodeResult(newResp.result, as: ACPSessionNewResult.self)

        let promptReq = JSONRPCRequest(
            id: .int(103),
            method: ACPMethods.sessionPrompt,
            params: try ACPCodec.encodeParams(ACPSessionPromptParams(sessionId: newResult.sessionId, prompt: [.text("hello")]))
        )
        let promptResp = await service.handle(promptReq)
        XCTAssertNil(promptResp.error)
    }

    func testInitializeAndSessionPrompt() async throws {
        let notifications = NotificationBox()

        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: EchoTestClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(loadSession: true),
            notificationSink: { n in await notifications.append(n) }
        )

        let initReq = JSONRPCRequest(
            id: .int(1),
            method: ACPMethods.initialize,
            params: try ACPCodec.encodeParams(ACPInitializeParams(protocolVersion: 1))
        )
        let initResp = await service.handle(initReq)
        XCTAssertNil(initResp.error)

        let newReq = JSONRPCRequest(
            id: .int(2),
            method: ACPMethods.sessionNew,
            params: try ACPCodec.encodeParams(ACPSessionNewParams(cwd: "/tmp"))
        )
        let newResp = await service.handle(newReq)
        let newResult = try ACPCodec.decodeResult(newResp.result, as: ACPSessionNewResult.self)

        let promptReq = JSONRPCRequest(
            id: .int(3),
            method: ACPMethods.sessionPrompt,
            params: try ACPCodec.encodeParams(ACPSessionPromptParams(sessionId: newResult.sessionId, prompt: [.text("hello")]))
        )
        let promptResp = await service.handle(promptReq)
        let promptResult = try ACPCodec.decodeResult(promptResp.result, as: ACPSessionPromptResult.self)
        XCTAssertEqual(promptResult.stopReason, .endTurn)
        let values = await notifications.snapshot()
        XCTAssertFalse(values.isEmpty)
    }

    func testPromptEmitsUpdateLifecycleBeforeMessageChunk() async throws {
        let notifications = NotificationBox()
        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: EchoTestClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(loadSession: true),
            notificationSink: { n in await notifications.append(n) }
        )

        let newReq = JSONRPCRequest(
            id: .int(9991),
            method: ACPMethods.sessionNew,
            params: try ACPCodec.encodeParams(ACPSessionNewParams(cwd: "/tmp"))
        )
        let newResp = await service.handle(newReq)
        let session = try ACPCodec.decodeResult(newResp.result, as: ACPSessionNewResult.self)

        let promptReq = JSONRPCRequest(
            id: .int(9992),
            method: ACPMethods.sessionPrompt,
            params: try ACPCodec.encodeParams(ACPSessionPromptParams(sessionId: session.sessionId, prompt: [.text("hello")]))
        )
        let promptResp = await service.handle(promptReq)
        XCTAssertNil(promptResp.error)

        let values = await notifications.snapshot()
        XCTAssertGreaterThanOrEqual(values.count, 5)
        let updates = try values.map { try ACPCodec.decodeParams($0.params, as: ACPSessionUpdateParams.self) }
        XCTAssertEqual(updates[0].update.sessionUpdate, .availableCommandsUpdate)
        XCTAssertEqual(updates[1].update.sessionUpdate, .plan)
        XCTAssertEqual(updates[2].update.sessionUpdate, .toolCall)
        XCTAssertEqual(updates[3].update.sessionUpdate, .toolCallUpdate)
        XCTAssertEqual(updates[4].update.sessionUpdate, .agentMessageChunk)
        XCTAssertEqual(updates[0].update.availableCommands?.first?.name, "read_file")
        XCTAssertEqual(updates[1].update.plan?.entries.first?.content, "Analyze prompt")
    }

    func testPromptEmitsExecutionStateLifecycleWhenEnabled() async throws {
        let notifications = NotificationBox()
        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: EchoTestClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(loadSession: true),
            options: .init(promptExecution: .init(enableStateUpdates: true)),
            notificationSink: { n in await notifications.append(n) }
        )

        let newReq = JSONRPCRequest(
            id: .int(9993),
            method: ACPMethods.sessionNew,
            params: try ACPCodec.encodeParams(ACPSessionNewParams(cwd: "/tmp"))
        )
        let newResp = await service.handle(newReq)
        let session = try ACPCodec.decodeResult(newResp.result, as: ACPSessionNewResult.self)

        let promptReq = JSONRPCRequest(
            id: .int(9994),
            method: ACPMethods.sessionPrompt,
            params: try ACPCodec.encodeParams(ACPSessionPromptParams(sessionId: session.sessionId, prompt: [.text("hello")]))
        )
        let promptResp = await service.handle(promptReq)
        XCTAssertNil(promptResp.error)

        let updates = try await notifications.snapshot()
            .map { try ACPCodec.decodeParams($0.params, as: ACPSessionUpdateParams.self) }

        let queuedIndex = try XCTUnwrap(updates.firstIndex(where: {
            $0.update.sessionUpdate == .executionStateUpdate && $0.update.executionStateUpdate?.state == .queued
        }))
        let runningIndex = try XCTUnwrap(updates.firstIndex(where: {
            $0.update.sessionUpdate == .executionStateUpdate && $0.update.executionStateUpdate?.state == .running
        }))
        let completedIndex = try XCTUnwrap(updates.firstIndex(where: {
            $0.update.sessionUpdate == .executionStateUpdate && $0.update.executionStateUpdate?.state == .completed
        }))
        let firstLifecycleIndex = try XCTUnwrap(updates.firstIndex(where: { $0.update.sessionUpdate == .availableCommandsUpdate }))
        let messageIndex = try XCTUnwrap(updates.firstIndex(where: { $0.update.sessionUpdate == .agentMessageChunk }))

        XCTAssertLessThan(queuedIndex, runningIndex)
        XCTAssertLessThan(runningIndex, firstLifecycleIndex)
        XCTAssertGreaterThan(completedIndex, messageIndex)
    }

    func testMethodNotFoundReturnsJSONRPCMethodNotFound() async throws {
        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: EchoTestClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(loadSession: true),
            notificationSink: { _ in }
        )

        let req = JSONRPCRequest(id: .int(999), method: "not/exist", params: nil)
        let resp = await service.handle(req)
        XCTAssertEqual(resp.error?.code, JSONRPCErrorCode.methodNotFound)
    }

    func testPromptCanBeCancelled() async throws {
        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: SlowCancellableClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(loadSession: true),
            notificationSink: { _ in }
        )

        let newReq = JSONRPCRequest(
            id: .int(10),
            method: ACPMethods.sessionNew,
            params: try ACPCodec.encodeParams(ACPSessionNewParams(cwd: "/tmp"))
        )
        let newResp = await service.handle(newReq)
        let newResult = try ACPCodec.decodeResult(newResp.result, as: ACPSessionNewResult.self)

        let promptReq = JSONRPCRequest(
            id: .int(11),
            method: ACPMethods.sessionPrompt,
            params: try ACPCodec.encodeParams(ACPSessionPromptParams(sessionId: newResult.sessionId, prompt: [.text("will cancel")]))
        )

        let promptTask = Task {
            await service.handle(promptReq)
        }

        try await Task.sleep(nanoseconds: 60_000_000)
        await service.handleCancel(JSONRPCNotification(
            method: ACPMethods.sessionCancel,
            params: try ACPCodec.encodeParams(ACPSessionCancelParams(sessionId: newResult.sessionId))
        ))

        let promptResp = await promptTask.value
        let promptResult = try ACPCodec.decodeResult(promptResp.result, as: ACPSessionPromptResult.self)
        XCTAssertEqual(promptResult.stopReason, .cancelled)
    }

    func testPromptCanBeStoppedBySessionStopRequest() async throws {
        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: SlowCancellableClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(loadSession: true),
            notificationSink: { _ in }
        )

        let newReq = JSONRPCRequest(
            id: .int(210),
            method: ACPMethods.sessionNew,
            params: try ACPCodec.encodeParams(ACPSessionNewParams(cwd: "/tmp"))
        )
        let newResp = await service.handle(newReq)
        let newResult = try ACPCodec.decodeResult(newResp.result, as: ACPSessionNewResult.self)

        let promptReq = JSONRPCRequest(
            id: .int(211),
            method: ACPMethods.sessionPrompt,
            params: try ACPCodec.encodeParams(ACPSessionPromptParams(sessionId: newResult.sessionId, prompt: [.text("will stop")]))
        )
        let promptTask = Task { await service.handle(promptReq) }

        try await Task.sleep(nanoseconds: 60_000_000)
        let stopReq = JSONRPCRequest(
            id: .int(212),
            method: ACPMethods.sessionStop,
            params: try ACPCodec.encodeParams(ACPSessionCancelParams(sessionId: newResult.sessionId))
        )
        let stopResp = await service.handle(stopReq)
        XCTAssertNil(stopResp.error)
        _ = try ACPCodec.decodeResult(stopResp.result, as: ACPSessionStopResult.self)

        let promptResp = await promptTask.value
        let promptResult = try ACPCodec.decodeResult(promptResp.result, as: ACPSessionPromptResult.self)
        XCTAssertEqual(promptResult.stopReason, .cancelled)
    }

    func testPromptCanBeCancelledByProtocolCancelRequest() async throws {
        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: SlowCancellableClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(loadSession: true),
            notificationSink: { _ in }
        )

        let newReq = JSONRPCRequest(
            id: .int(12),
            method: ACPMethods.sessionNew,
            params: try ACPCodec.encodeParams(ACPSessionNewParams(cwd: "/tmp"))
        )
        let newResp = await service.handle(newReq)
        let newResult = try ACPCodec.decodeResult(newResp.result, as: ACPSessionNewResult.self)

        let promptReq = JSONRPCRequest(
            id: .int(13),
            method: ACPMethods.sessionPrompt,
            params: try ACPCodec.encodeParams(ACPSessionPromptParams(sessionId: newResult.sessionId, prompt: [.text("will cancel by request id")]))
        )

        let promptTask = Task {
            await service.handle(promptReq)
        }

        try await Task.sleep(nanoseconds: 60_000_000)
        await service.handleCancel(JSONRPCNotification(
            method: ACPMethods.cancelRequest,
            params: try ACPCodec.encodeParams(ACPCancelRequestParams(requestId: .int(13)))
        ))

        let promptResp = await promptTask.value
        XCTAssertEqual(promptResp.error?.code, JSONRPCErrorCode.requestCancelled)
    }

    func testPromptCanBeCancelledByProtocolCancelRequestDuringPermissionStage() async throws {
        actor PermissionGate {
            private var released = false
            private var waiters: [CheckedContinuation<Void, Never>] = []

            func waitUntilReleased() async {
                if released { return }
                await withCheckedContinuation { continuation in
                    waiters.append(continuation)
                }
            }

            func release() {
                released = true
                let continuations = waiters
                waiters.removeAll()
                continuations.forEach { $0.resume() }
            }
        }

        let gate = PermissionGate()
        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: EchoTestClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(loadSession: true),
            permissionRequester: { _ in
                await gate.waitUntilReleased()
                return .init(outcome: .selected(.init(optionId: "allow_once")))
            },
            notificationSink: { _ in }
        )

        let newReq = JSONRPCRequest(
            id: .int(14),
            method: ACPMethods.sessionNew,
            params: try ACPCodec.encodeParams(ACPSessionNewParams(cwd: "/tmp"))
        )
        let newResp = await service.handle(newReq)
        let newResult = try ACPCodec.decodeResult(newResp.result, as: ACPSessionNewResult.self)

        let promptReq = JSONRPCRequest(
            id: .int(15),
            method: ACPMethods.sessionPrompt,
            params: try ACPCodec.encodeParams(ACPSessionPromptParams(sessionId: newResult.sessionId, prompt: [.text("cancel during permission")]))
        )
        let promptTask = Task { await service.handle(promptReq) }

        try await Task.sleep(nanoseconds: 30_000_000)
        await service.handleCancel(
            .init(
                method: ACPMethods.cancelRequest,
                params: try ACPCodec.encodeParams(ACPCancelRequestParams(requestId: .int(15)))
            )
        )
        await gate.release()

        let promptResp = await promptTask.value
        XCTAssertEqual(promptResp.error?.code, JSONRPCErrorCode.requestCancelled)
    }

    func testPromptPreCancelledByProtocolStringRequestIDMatchesIntPromptID() async throws {
        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: EchoTestClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(loadSession: true),
            notificationSink: { _ in }
        )

        let newReq = JSONRPCRequest(
            id: .int(16),
            method: ACPMethods.sessionNew,
            params: try ACPCodec.encodeParams(ACPSessionNewParams(cwd: "/tmp"))
        )
        let newResp = await service.handle(newReq)
        let newResult = try ACPCodec.decodeResult(newResp.result, as: ACPSessionNewResult.self)

        await service.handleCancel(
            .init(
                method: ACPMethods.cancelRequest,
                params: try ACPCodec.encodeParams(ACPCancelRequestParams(requestId: .string("s2c-17")))
            )
        )

        let promptReq = JSONRPCRequest(
            id: .int(17),
            method: ACPMethods.sessionPrompt,
            params: try ACPCodec.encodeParams(
                ACPSessionPromptParams(sessionId: newResult.sessionId, prompt: [.text("pre-cancel fallback string->int")])
            )
        )
        let promptResp = await service.handle(promptReq)
        XCTAssertEqual(promptResp.error?.code, JSONRPCErrorCode.requestCancelled)
    }

    func testPromptPreCancelledByProtocolIntRequestIDMatchesStringPromptID() async throws {
        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: EchoTestClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(loadSession: true),
            notificationSink: { _ in }
        )

        let newReq = JSONRPCRequest(
            id: .int(18),
            method: ACPMethods.sessionNew,
            params: try ACPCodec.encodeParams(ACPSessionNewParams(cwd: "/tmp"))
        )
        let newResp = await service.handle(newReq)
        let newResult = try ACPCodec.decodeResult(newResp.result, as: ACPSessionNewResult.self)

        await service.handleCancel(
            .init(
                method: ACPMethods.cancelRequest,
                params: try ACPCodec.encodeParams(ACPCancelRequestParams(requestId: .int(19)))
            )
        )

        let promptReq = JSONRPCRequest(
            id: .string("s2c-19"),
            method: ACPMethods.sessionPrompt,
            params: try ACPCodec.encodeParams(
                ACPSessionPromptParams(sessionId: newResult.sessionId, prompt: [.text("pre-cancel fallback int->string")])
            )
        )
        let promptResp = await service.handle(promptReq)
        XCTAssertEqual(promptResp.error?.code, JSONRPCErrorCode.requestCancelled)
    }

    func testPreCancelledRequestIsConsumedOnlyOnceForIntToStringFallback() async throws {
        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: EchoTestClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(loadSession: true),
            notificationSink: { _ in }
        )

        let newReq = JSONRPCRequest(
            id: .int(20),
            method: ACPMethods.sessionNew,
            params: try ACPCodec.encodeParams(ACPSessionNewParams(cwd: "/tmp"))
        )
        let newResp = await service.handle(newReq)
        let session = try ACPCodec.decodeResult(newResp.result, as: ACPSessionNewResult.self)

        await service.handleCancel(
            .init(
                method: ACPMethods.cancelRequest,
                params: try ACPCodec.encodeParams(ACPCancelRequestParams(requestId: .int(21)))
            )
        )

        let firstPrompt = JSONRPCRequest(
            id: .string("s2c-21"),
            method: ACPMethods.sessionPrompt,
            params: try ACPCodec.encodeParams(
                ACPSessionPromptParams(sessionId: session.sessionId, prompt: [.text("consume once #1")])
            )
        )
        let firstResponse = await service.handle(firstPrompt)
        XCTAssertEqual(firstResponse.error?.code, JSONRPCErrorCode.requestCancelled)

        let secondPrompt = JSONRPCRequest(
            id: .int(21),
            method: ACPMethods.sessionPrompt,
            params: try ACPCodec.encodeParams(
                ACPSessionPromptParams(sessionId: session.sessionId, prompt: [.text("consume once #2")])
            )
        )
        let secondResponse = await service.handle(secondPrompt)
        let secondResult = try ACPCodec.decodeResult(secondResponse.result, as: ACPSessionPromptResult.self)
        XCTAssertEqual(secondResult.stopReason, .endTurn)
    }

    func testPreCancelledRequestIsConsumedOnlyOnceForStringToIntFallback() async throws {
        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: EchoTestClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(loadSession: true),
            notificationSink: { _ in }
        )

        let newReq = JSONRPCRequest(
            id: .int(22),
            method: ACPMethods.sessionNew,
            params: try ACPCodec.encodeParams(ACPSessionNewParams(cwd: "/tmp"))
        )
        let newResp = await service.handle(newReq)
        let session = try ACPCodec.decodeResult(newResp.result, as: ACPSessionNewResult.self)

        await service.handleCancel(
            .init(
                method: ACPMethods.cancelRequest,
                params: try ACPCodec.encodeParams(ACPCancelRequestParams(requestId: .string("s2c-23")))
            )
        )

        let firstPrompt = JSONRPCRequest(
            id: .int(23),
            method: ACPMethods.sessionPrompt,
            params: try ACPCodec.encodeParams(
                ACPSessionPromptParams(sessionId: session.sessionId, prompt: [.text("consume once #1")])
            )
        )
        let firstResponse = await service.handle(firstPrompt)
        XCTAssertEqual(firstResponse.error?.code, JSONRPCErrorCode.requestCancelled)

        let secondPrompt = JSONRPCRequest(
            id: .string("s2c-23"),
            method: ACPMethods.sessionPrompt,
            params: try ACPCodec.encodeParams(
                ACPSessionPromptParams(sessionId: session.sessionId, prompt: [.text("consume once #2")])
            )
        )
        let secondResponse = await service.handle(secondPrompt)
        let secondResult = try ACPCodec.decodeResult(secondResponse.result, as: ACPSessionPromptResult.self)
        XCTAssertEqual(secondResult.stopReason, .endTurn)
    }

    func testPromptCancellationEmitsExecutionStateWhenEnabled() async throws {
        let notifications = NotificationBox()
        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: SlowCancellableClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(loadSession: true),
            options: .init(promptExecution: .init(enableStateUpdates: true)),
            notificationSink: { n in await notifications.append(n) }
        )

        let newReq = JSONRPCRequest(
            id: .int(1200),
            method: ACPMethods.sessionNew,
            params: try ACPCodec.encodeParams(ACPSessionNewParams(cwd: "/tmp"))
        )
        let newResp = await service.handle(newReq)
        let session = try ACPCodec.decodeResult(newResp.result, as: ACPSessionNewResult.self)

        let promptReq = JSONRPCRequest(
            id: .int(1201),
            method: ACPMethods.sessionPrompt,
            params: try ACPCodec.encodeParams(ACPSessionPromptParams(sessionId: session.sessionId, prompt: [.text("cancel path")]))
        )
        let promptTask = Task { await service.handle(promptReq) }

        try await Task.sleep(nanoseconds: 60_000_000)
        await service.handleCancel(
            .init(
                method: ACPMethods.sessionCancel,
                params: try ACPCodec.encodeParams(ACPSessionCancelParams(sessionId: session.sessionId))
            )
        )
        _ = await promptTask.value

        let updates = try await notifications.snapshot()
            .map { try ACPCodec.decodeParams($0.params, as: ACPSessionUpdateParams.self) }
        XCTAssertTrue(updates.contains(where: {
            $0.update.sessionUpdate == .executionStateUpdate
                && $0.update.executionStateUpdate?.state == .cancelled
        }))
    }

    func testPromptRetriesThenSucceedsWhenConfigured() async throws {
        await RetryOnceClient.resetCounter()
        let notifications = NotificationBox()
        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: RetryOnceClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(loadSession: true),
            options: .init(
                promptExecution: .init(
                    enableStateUpdates: true,
                    maxRetries: 1,
                    retryBaseDelayNanoseconds: 1_000_000
                )
            ),
            notificationSink: { n in await notifications.append(n) }
        )

        let newReq = JSONRPCRequest(
            id: .int(1202),
            method: ACPMethods.sessionNew,
            params: try ACPCodec.encodeParams(ACPSessionNewParams(cwd: "/tmp"))
        )
        let newResp = await service.handle(newReq)
        let session = try ACPCodec.decodeResult(newResp.result, as: ACPSessionNewResult.self)

        let promptReq = JSONRPCRequest(
            id: .int(1203),
            method: ACPMethods.sessionPrompt,
            params: try ACPCodec.encodeParams(ACPSessionPromptParams(sessionId: session.sessionId, prompt: [.text("retry me")]))
        )
        let promptResp = await service.handle(promptReq)
        XCTAssertNil(promptResp.error)
        let promptResult = try ACPCodec.decodeResult(promptResp.result, as: ACPSessionPromptResult.self)
        XCTAssertEqual(promptResult.stopReason, .endTurn)

        let updates = try await notifications.snapshot()
            .map { try ACPCodec.decodeParams($0.params, as: ACPSessionUpdateParams.self) }
        XCTAssertTrue(updates.contains(where: {
            $0.update.sessionUpdate == .executionStateUpdate
                && $0.update.executionStateUpdate?.state == .retrying
        }))
        XCTAssertTrue(updates.contains(where: { $0.update.sessionUpdate == .retryUpdate }))
        XCTAssertTrue(updates.contains(where: {
            $0.update.sessionUpdate == .executionStateUpdate
                && $0.update.executionStateUpdate?.state == .completed
        }))
    }

    func testPromptRetryExhaustedReturnsInternalError() async throws {
        let notifications = NotificationBox()
        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: AlwaysFailClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(loadSession: true),
            options: .init(
                promptExecution: .init(
                    enableStateUpdates: true,
                    maxRetries: 1,
                    retryBaseDelayNanoseconds: 1_000_000
                )
            ),
            notificationSink: { n in await notifications.append(n) }
        )

        let newReq = JSONRPCRequest(
            id: .int(1204),
            method: ACPMethods.sessionNew,
            params: try ACPCodec.encodeParams(ACPSessionNewParams(cwd: "/tmp"))
        )
        let newResp = await service.handle(newReq)
        let session = try ACPCodec.decodeResult(newResp.result, as: ACPSessionNewResult.self)

        let promptReq = JSONRPCRequest(
            id: .int(1205),
            method: ACPMethods.sessionPrompt,
            params: try ACPCodec.encodeParams(ACPSessionPromptParams(sessionId: session.sessionId, prompt: [.text("always fail")]))
        )
        let promptResp = await service.handle(promptReq)
        XCTAssertEqual(promptResp.error?.code, JSONRPCErrorCode.internalError)

        let updates = try await notifications.snapshot()
            .map { try ACPCodec.decodeParams($0.params, as: ACPSessionUpdateParams.self) }
        XCTAssertTrue(updates.contains(where: {
            $0.update.sessionUpdate == .executionStateUpdate
                && $0.update.executionStateUpdate?.state == .failed
        }))
        XCTAssertEqual(updates.filter { $0.update.sessionUpdate == .retryUpdate }.count, 1)
    }

    func testPromptEmitsTelemetryLifecycle() async throws {
        let telemetry = TelemetryBox()
        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: EchoTestClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(loadSession: true),
            telemetrySink: { event in await telemetry.append(event) },
            notificationSink: { _ in }
        )

        let newReq = JSONRPCRequest(
            id: .int(1300),
            method: ACPMethods.sessionNew,
            params: try ACPCodec.encodeParams(ACPSessionNewParams(cwd: "/tmp"))
        )
        let newResp = await service.handle(newReq)
        let session = try ACPCodec.decodeResult(newResp.result, as: ACPSessionNewResult.self)

        let promptReq = JSONRPCRequest(
            id: .int(1301),
            method: ACPMethods.sessionPrompt,
            params: try ACPCodec.encodeParams(ACPSessionPromptParams(sessionId: session.sessionId, prompt: [.text("telemetry")]))
        )
        let promptResp = await service.handle(promptReq)
        XCTAssertNil(promptResp.error)

        let names = await telemetry.snapshot().map(\.name)
        XCTAssertTrue(names.contains("session_new"))
        XCTAssertTrue(names.contains("prompt_requested"))
        XCTAssertTrue(names.contains("prompt_started"))
        XCTAssertTrue(names.contains("prompt_completed"))
    }

    func testPromptRetryEmitsTelemetryRetryEvent() async throws {
        await RetryOnceClient.resetCounter()
        let telemetry = TelemetryBox()
        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: RetryOnceClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(loadSession: true),
            options: .init(
                promptExecution: .init(
                    enableStateUpdates: true,
                    maxRetries: 1,
                    retryBaseDelayNanoseconds: 1_000_000
                )
            ),
            telemetrySink: { event in await telemetry.append(event) },
            notificationSink: { _ in }
        )

        let newResp = await service.handle(
            .init(
                id: .int(1302),
                method: ACPMethods.sessionNew,
                params: try ACPCodec.encodeParams(ACPSessionNewParams(cwd: "/tmp"))
            )
        )
        let session = try ACPCodec.decodeResult(newResp.result, as: ACPSessionNewResult.self)
        let promptResp = await service.handle(
            .init(
                id: .int(1303),
                method: ACPMethods.sessionPrompt,
                params: try ACPCodec.encodeParams(ACPSessionPromptParams(sessionId: session.sessionId, prompt: [.text("retry telemetry")]))
            )
        )
        XCTAssertNil(promptResp.error)

        let events = await telemetry.snapshot()
        let retryEvent = events.first(where: { $0.name == "prompt_retry" })
        XCTAssertNotNil(retryEvent)
        XCTAssertEqual(retryEvent?.attributes["attempt"], "1")
    }

    func testTelemetryExtensionDoesNotLeakIntoProtocolPayload() async throws {
        let notifications = NotificationBox()
        let telemetry = TelemetryBox()
        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: EchoTestClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(loadSession: true),
            telemetrySink: { event in await telemetry.append(event) },
            notificationSink: { n in await notifications.append(n) }
        )

        let newResp = await service.handle(
            .init(
                id: .int(1310),
                method: ACPMethods.sessionNew,
                params: try ACPCodec.encodeParams(ACPSessionNewParams(cwd: "/tmp"))
            )
        )
        let session = try ACPCodec.decodeResult(newResp.result, as: ACPSessionNewResult.self)

        let promptResp = await service.handle(
            .init(
                id: .int(1311),
                method: ACPMethods.sessionPrompt,
                params: try ACPCodec.encodeParams(ACPSessionPromptParams(sessionId: session.sessionId, prompt: [.text("hello")]))
            )
        )
        XCTAssertNil(promptResp.error)
        let telemetryEvents = await telemetry.snapshot()
        XCTAssertFalse(telemetryEvents.isEmpty)

        let responseJSON = try XCTUnwrap(
            String(data: JSONRPCCodec.encode(.response(promptResp)), encoding: .utf8)
        )
        XCTAssertFalse(responseJSON.contains("\"telemetry\""))
        XCTAssertFalse(responseJSON.contains("prompt_requested"))

        let payloads = try await notifications.snapshot().map {
            try XCTUnwrap(String(data: JSONRPCCodec.encode(.notification($0)), encoding: .utf8))
        }
        XCTAssertFalse(payloads.joined(separator: "\n").contains("\"telemetry\""))
        XCTAssertFalse(payloads.joined(separator: "\n").contains("prompt_requested"))
    }

    func testLogoutRequiresCapability() async throws {
        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: EchoTestClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(loadSession: true),
            notificationSink: { _ in }
        )
        let req = JSONRPCRequest(id: .int(14), method: ACPMethods.logout, params: try ACPCodec.encodeParams(ACPLogoutParams()))
        let resp = await service.handle(req)
        XCTAssertEqual(resp.error?.code, JSONRPCErrorCode.methodNotFound)
    }

    func testLogoutClearsSessionsWhenCapabilityEnabled() async throws {
        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: EchoTestClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(authCapabilities: .init(logout: .init()), sessionCapabilities: .init(list: .init()), loadSession: true),
            notificationSink: { _ in }
        )

        let newReq = JSONRPCRequest(
            id: .int(15),
            method: ACPMethods.sessionNew,
            params: try ACPCodec.encodeParams(ACPSessionNewParams(cwd: "/tmp"))
        )
        _ = await service.handle(newReq)

        let logoutReq = JSONRPCRequest(id: .int(16), method: ACPMethods.logout, params: try ACPCodec.encodeParams(ACPLogoutParams()))
        let logoutResp = await service.handle(logoutReq)
        XCTAssertNil(logoutResp.error)

        let listReq = JSONRPCRequest(
            id: .int(17),
            method: ACPMethods.sessionList,
            params: try ACPCodec.encodeParams(ACPSessionListParams())
        )
        let listResp = await service.handle(listReq)
        let listResult = try ACPCodec.decodeResult(listResp.result, as: ACPSessionListResult.self)
        XCTAssertEqual(listResult.sessions.count, 0)
    }

    func testPromptTimeoutReturnsInternalError() async throws {
        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: SlowCancellableClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(loadSession: true),
            options: .init(promptTimeoutNanoseconds: 50_000_000),
            notificationSink: { _ in }
        )

        let newReq = JSONRPCRequest(
            id: .int(20),
            method: ACPMethods.sessionNew,
            params: try ACPCodec.encodeParams(ACPSessionNewParams(cwd: "/tmp"))
        )
        let newResp = await service.handle(newReq)
        let newResult = try ACPCodec.decodeResult(newResp.result, as: ACPSessionNewResult.self)

        let promptReq = JSONRPCRequest(
            id: .int(21),
            method: ACPMethods.sessionPrompt,
            params: try ACPCodec.encodeParams(ACPSessionPromptParams(sessionId: newResult.sessionId, prompt: [.text("timeout")]))
        )
        let promptResp = await service.handle(promptReq)
        XCTAssertEqual(promptResp.error?.code, JSONRPCErrorCode.internalError)
    }

    func testSessionTTLExpiresAndLoadReturnsInvalidParams() async throws {
        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: EchoTestClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(loadSession: true),
            options: .init(sessionTTLNanos: 30_000_000),
            notificationSink: { _ in }
        )

        let newReq = JSONRPCRequest(
            id: .int(30),
            method: ACPMethods.sessionNew,
            params: try ACPCodec.encodeParams(ACPSessionNewParams(cwd: "/tmp"))
        )
        let newResp = await service.handle(newReq)
        let newResult = try ACPCodec.decodeResult(newResp.result, as: ACPSessionNewResult.self)

        try await Task.sleep(nanoseconds: 80_000_000)

        let loadReq = JSONRPCRequest(
            id: .int(31),
            method: ACPMethods.sessionLoad,
            params: try ACPCodec.encodeParams(ACPSessionLoadParams(sessionId: newResult.sessionId, cwd: "/tmp"))
        )
        let loadResp = await service.handle(loadReq)
        XCTAssertEqual(loadResp.error?.code, JSONRPCErrorCode.invalidParams)
    }

    func testInitializeMissingParamsReturnsInvalidParams() async throws {
        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: EchoTestClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(loadSession: true),
            notificationSink: { _ in }
        )

        let req = JSONRPCRequest(id: .int(41), method: ACPMethods.initialize, params: nil)
        let resp = await service.handle(req)
        XCTAssertEqual(resp.error?.code, JSONRPCErrorCode.invalidParams)
    }

    func testInitializeUnsupportedProtocolVersionReturnsInvalidParams() async throws {
        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: EchoTestClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(loadSession: true),
            notificationSink: { _ in }
        )

        let req = JSONRPCRequest(
            id: .int(410),
            method: ACPMethods.initialize,
            params: try ACPCodec.encodeParams(ACPInitializeParams(protocolVersion: 2))
        )
        let resp = await service.handle(req)
        XCTAssertEqual(resp.error?.code, JSONRPCErrorCode.invalidParams)
    }

    func testSessionLoadUnsupportedByCapabilitiesReturnsMethodNotFound() async throws {
        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: EchoTestClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(loadSession: false),
            notificationSink: { _ in }
        )

        let req = JSONRPCRequest(
            id: .int(411),
            method: ACPMethods.sessionLoad,
            params: try ACPCodec.encodeParams(ACPSessionLoadParams(sessionId: "sess_x", cwd: "/tmp"))
        )
        let resp = await service.handle(req)
        XCTAssertEqual(resp.error?.code, JSONRPCErrorCode.methodNotFound)
    }

    func testSessionLoadRestoresPersistedTranscriptWhenSessionNotInMemory() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("acp-session-load-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let service1 = ACPAgentService(
            agentSessionFactory: { SKIAgentSession(client: HistoryEchoClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(loadSession: true),
            options: .init(
                sessionPersistence: .init(directoryURL: tempDir)
            ),
            notificationSink: { _ in }
        )

        let newResp = await service1.handle(JSONRPCRequest(
            id: .int(412),
            method: ACPMethods.sessionNew,
            params: try ACPCodec.encodeParams(ACPSessionNewParams(cwd: "/tmp"))
        ))
        let session = try ACPCodec.decodeResult(newResp.result, as: ACPSessionNewResult.self)

        _ = await service1.handle(JSONRPCRequest(
            id: .int(413),
            method: ACPMethods.sessionPrompt,
            params: try ACPCodec.encodeParams(ACPSessionPromptParams(sessionId: session.sessionId, prompt: [.text("persisted one")]))
        ))

        let notifications = NotificationBox()
        let service2 = ACPAgentService(
            agentSessionFactory: { SKIAgentSession(client: HistoryEchoClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(loadSession: true),
            options: .init(
                sessionPersistence: .init(directoryURL: tempDir)
            ),
            notificationSink: { n in await notifications.append(n) }
        )

        let loadResp = await service2.handle(JSONRPCRequest(
            id: .int(414),
            method: ACPMethods.sessionLoad,
            params: try ACPCodec.encodeParams(ACPSessionLoadParams(sessionId: session.sessionId, cwd: "/tmp"))
        ))
        XCTAssertNil(loadResp.error)

        _ = await service2.handle(JSONRPCRequest(
            id: .int(415),
            method: ACPMethods.sessionPrompt,
            params: try ACPCodec.encodeParams(ACPSessionPromptParams(sessionId: session.sessionId, prompt: [.text("persisted two")]))
        ))

        let updates: [ACPSessionUpdateParams] = try await notifications.snapshot()
            .map { try ACPCodec.decodeParams($0.params, as: ACPSessionUpdateParams.self) }
        let textChunks = updates
            .filter { $0.sessionId == session.sessionId && $0.update.sessionUpdate == .agentMessageChunk }
            .compactMap { $0.update.content?.text }
        XCTAssertTrue(textChunks.contains(where: {
            $0.contains("persisted one")
            && $0.contains("ok-history:")
            && $0.contains("persisted two")
        }))
    }

    func testSessionNewFactoryErrorReturnsInternalError() async throws {
        let service = ACPAgentService(
            sessionFactory: {
                throw NSError(domain: "ACPAgentServiceTests", code: 500, userInfo: [NSLocalizedDescriptionKey: "factory failed"])
            },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(loadSession: true),
            notificationSink: { _ in }
        )

        let req = JSONRPCRequest(
            id: .int(42),
            method: ACPMethods.sessionNew,
            params: try ACPCodec.encodeParams(ACPSessionNewParams(cwd: "/tmp"))
        )
        let resp = await service.handle(req)
        XCTAssertEqual(resp.error?.code, JSONRPCErrorCode.internalError)
    }

    func testPromptWhileRunningReturnsInvalidParams() async throws {
        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: SlowCancellableClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(loadSession: true),
            notificationSink: { _ in }
        )

        let newReq = JSONRPCRequest(
            id: .int(50),
            method: ACPMethods.sessionNew,
            params: try ACPCodec.encodeParams(ACPSessionNewParams(cwd: "/tmp"))
        )
        let newResp = await service.handle(newReq)
        let newResult = try ACPCodec.decodeResult(newResp.result, as: ACPSessionNewResult.self)

        let firstPrompt = JSONRPCRequest(
            id: .int(51),
            method: ACPMethods.sessionPrompt,
            params: try ACPCodec.encodeParams(ACPSessionPromptParams(sessionId: newResult.sessionId, prompt: [.text("first")]))
        )
        let firstTask = Task { await service.handle(firstPrompt) }

        try await Task.sleep(nanoseconds: 40_000_000)

        let secondPrompt = JSONRPCRequest(
            id: .int(52),
            method: ACPMethods.sessionPrompt,
            params: try ACPCodec.encodeParams(ACPSessionPromptParams(sessionId: newResult.sessionId, prompt: [.text("second")]))
        )
        let secondResp = await service.handle(secondPrompt)
        XCTAssertEqual(secondResp.error?.code, JSONRPCErrorCode.invalidParams)

        await service.handleCancel(JSONRPCNotification(
            method: ACPMethods.sessionCancel,
            params: try ACPCodec.encodeParams(ACPSessionCancelParams(sessionId: newResult.sessionId))
        ))
        _ = await firstTask.value
    }

    func testCancelIsIdempotent() async throws {
        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: SlowCancellableClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(loadSession: true),
            notificationSink: { _ in }
        )

        let newReq = JSONRPCRequest(
            id: .int(60),
            method: ACPMethods.sessionNew,
            params: try ACPCodec.encodeParams(ACPSessionNewParams(cwd: "/tmp"))
        )
        let newResp = await service.handle(newReq)
        let newResult = try ACPCodec.decodeResult(newResp.result, as: ACPSessionNewResult.self)

        let promptReq = JSONRPCRequest(
            id: .int(61),
            method: ACPMethods.sessionPrompt,
            params: try ACPCodec.encodeParams(ACPSessionPromptParams(sessionId: newResult.sessionId, prompt: [.text("cancel me")]))
        )

        let promptTask = Task { await service.handle(promptReq) }
        try await Task.sleep(nanoseconds: 30_000_000)

        let cancel = JSONRPCNotification(
            method: ACPMethods.sessionCancel,
            params: try ACPCodec.encodeParams(ACPSessionCancelParams(sessionId: newResult.sessionId))
        )
        await service.handleCancel(cancel)
        await service.handleCancel(cancel)

        let resp = await promptTask.value
        let result = try ACPCodec.decodeResult(resp.result, as: ACPSessionPromptResult.self)
        XCTAssertEqual(result.stopReason, .cancelled)
    }

    func testCancelledPromptDoesNotEmitSessionUpdate() async throws {
        let notifications = NotificationBox()
        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: SlowCancellableClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(loadSession: true),
            notificationSink: { n in await notifications.append(n) }
        )

        let newReq = JSONRPCRequest(
            id: .int(70),
            method: ACPMethods.sessionNew,
            params: try ACPCodec.encodeParams(ACPSessionNewParams(cwd: "/tmp"))
        )
        let newResp = await service.handle(newReq)
        let newResult = try ACPCodec.decodeResult(newResp.result, as: ACPSessionNewResult.self)

        let promptReq = JSONRPCRequest(
            id: .int(71),
            method: ACPMethods.sessionPrompt,
            params: try ACPCodec.encodeParams(ACPSessionPromptParams(sessionId: newResult.sessionId, prompt: [.text("cancel path")]))
        )
        let promptTask = Task { await service.handle(promptReq) }
        try await Task.sleep(nanoseconds: 30_000_000)
        await service.handleCancel(.init(
            method: ACPMethods.sessionCancel,
            params: try ACPCodec.encodeParams(ACPSessionCancelParams(sessionId: newResult.sessionId))
        ))

        _ = await promptTask.value
        let values = await notifications.snapshot()
        XCTAssertTrue(values.isEmpty)
    }

    func testTimeoutPromptDoesNotEmitSessionUpdate() async throws {
        let notifications = NotificationBox()
        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: SlowCancellableClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(loadSession: true),
            options: .init(promptTimeoutNanoseconds: 40_000_000),
            notificationSink: { n in await notifications.append(n) }
        )

        let newReq = JSONRPCRequest(
            id: .int(72),
            method: ACPMethods.sessionNew,
            params: try ACPCodec.encodeParams(ACPSessionNewParams(cwd: "/tmp"))
        )
        let newResp = await service.handle(newReq)
        let newResult = try ACPCodec.decodeResult(newResp.result, as: ACPSessionNewResult.self)

        let promptReq = JSONRPCRequest(
            id: .int(73),
            method: ACPMethods.sessionPrompt,
            params: try ACPCodec.encodeParams(ACPSessionPromptParams(sessionId: newResult.sessionId, prompt: [.text("timeout path")]))
        )
        let promptResp = await service.handle(promptReq)
        XCTAssertEqual(promptResp.error?.code, JSONRPCErrorCode.internalError)

        let values = await notifications.snapshot()
        XCTAssertTrue(values.isEmpty)
    }

    func testPermissionDeniedShortCircuitsPromptWithoutSessionUpdate() async throws {
        let notifications = NotificationBox()
        let counter = PromptCallCounter()
        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: CountingEchoClient(counter: counter)) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(loadSession: true),
            permissionRequester: { params in
                XCTAssertEqual(params.toolCall.title, "Execute session prompt")
                return .init(outcome: .cancelled)
            },
            notificationSink: { n in await notifications.append(n) }
        )

        let newReq = JSONRPCRequest(
            id: .int(80),
            method: ACPMethods.sessionNew,
            params: try ACPCodec.encodeParams(ACPSessionNewParams(cwd: "/tmp"))
        )
        let newResp = await service.handle(newReq)
        let newResult = try ACPCodec.decodeResult(newResp.result, as: ACPSessionNewResult.self)

        let promptReq = JSONRPCRequest(
            id: .int(81),
            method: ACPMethods.sessionPrompt,
            params: try ACPCodec.encodeParams(ACPSessionPromptParams(sessionId: newResult.sessionId, prompt: [.text("secret task")]))
        )
        let promptResp = await service.handle(promptReq)
        let result = try ACPCodec.decodeResult(promptResp.result, as: ACPSessionPromptResult.self)
        XCTAssertEqual(result.stopReason, .cancelled)

        let updateValues = await notifications.snapshot()
        XCTAssertTrue(updateValues.isEmpty)

        let calls = await counter.count
        XCTAssertEqual(calls, 0)
    }

    func testInitializeReturnsAuthMethodsAndAuthenticateSucceeds() async throws {
        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: EchoTestClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(loadSession: true),
            authMethods: [
                .init(id: "token", name: "Token")
            ],
            authenticationHandler: { params in
                XCTAssertEqual(params.methodId, "token")
            },
            notificationSink: { _ in }
        )

        let initReq = JSONRPCRequest(
            id: .int(90),
            method: ACPMethods.initialize,
            params: try ACPCodec.encodeParams(ACPInitializeParams(protocolVersion: 1))
        )
        let initResp = await service.handle(initReq)
        let initResult = try ACPCodec.decodeResult(initResp.result, as: ACPInitializeResult.self)
        XCTAssertEqual(initResult.authMethods.map(\.id), ["token"])

        let authReq = JSONRPCRequest(
            id: .int(91),
            method: ACPMethods.authenticate,
            params: try ACPCodec.encodeParams(ACPAuthenticateParams(methodId: "token"))
        )
        let authResp = await service.handle(authReq)
        XCTAssertNil(authResp.error)
    }

    func testSetModeEmitsCurrentModeUpdate() async throws {
        let notifications = NotificationBox()
        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: EchoTestClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(loadSession: true),
            options: .init(autoSessionInfoUpdateOnFirstPrompt: true),
            notificationSink: { n in await notifications.append(n) }
        )

        let newReq = JSONRPCRequest(
            id: .int(100),
            method: ACPMethods.sessionNew,
            params: try ACPCodec.encodeParams(ACPSessionNewParams(cwd: "/tmp"))
        )
        let newResp = await service.handle(newReq)
        let session = try ACPCodec.decodeResult(newResp.result, as: ACPSessionNewResult.self)

        let setModeReq = JSONRPCRequest(
            id: .int(101),
            method: ACPMethods.sessionSetMode,
            params: try ACPCodec.encodeParams(ACPSessionSetModeParams(sessionId: session.sessionId, modeId: "safe"))
        )
        let setModeResp = await service.handle(setModeReq)
        XCTAssertNil(setModeResp.error)

        let values = await notifications.snapshot()
        XCTAssertEqual(values.count, 1)
        let params = try ACPCodec.decodeParams(values[0].params, as: ACPSessionUpdateParams.self)
        XCTAssertEqual(params.update.sessionUpdate, .currentModeUpdate)
        XCTAssertEqual(params.update.currentModeId, "safe")
    }

    func testSetConfigOptionReturnsConfigOptionsAndEmitsUpdate() async throws {
        let notifications = NotificationBox()
        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: EchoTestClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(loadSession: true),
            notificationSink: { n in await notifications.append(n) }
        )

        let newReq = JSONRPCRequest(
            id: .int(110),
            method: ACPMethods.sessionNew,
            params: try ACPCodec.encodeParams(ACPSessionNewParams(cwd: "/tmp"))
        )
        let newResp = await service.handle(newReq)
        let session = try ACPCodec.decodeResult(newResp.result, as: ACPSessionNewResult.self)

        let setConfigReq = JSONRPCRequest(
            id: .int(111),
            method: ACPMethods.sessionSetConfigOption,
            params: try ACPCodec.encodeParams(ACPSessionSetConfigOptionParams(
                sessionId: session.sessionId,
                configId: "mode",
                value: "safe"
            ))
        )
        let setConfigResp = await service.handle(setConfigReq)
        let setConfigResult = try ACPCodec.decodeResult(setConfigResp.result, as: ACPSessionSetConfigOptionResult.self)
        XCTAssertEqual(setConfigResult.configOptions.first?.id, "mode")
        XCTAssertEqual(setConfigResult.configOptions.first?.currentValue, "safe")

        let values = await notifications.snapshot()
        XCTAssertEqual(values.count, 1)
        let params = try ACPCodec.decodeParams(values[0].params, as: ACPSessionUpdateParams.self)
        XCTAssertEqual(params.update.sessionUpdate, .configOptionUpdate)
        XCTAssertEqual(params.update.configOptions.first?.id, "mode")
        XCTAssertEqual(params.update.configOptions.first?.currentValue, "safe")
    }

    func testSetConfigOptionBooleanValueUsesBooleanKind() async throws {
        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: EchoTestClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(loadSession: true),
            notificationSink: { _ in }
        )

        let newReq = JSONRPCRequest(
            id: .int(113),
            method: ACPMethods.sessionNew,
            params: try ACPCodec.encodeParams(ACPSessionNewParams(cwd: "/tmp"))
        )
        let newResp = await service.handle(newReq)
        let session = try ACPCodec.decodeResult(newResp.result, as: ACPSessionNewResult.self)

        let setConfigReq = JSONRPCRequest(
            id: .int(114),
            method: ACPMethods.sessionSetConfigOption,
            params: try ACPCodec.encodeParams(ACPSessionSetConfigOptionParams(
                sessionId: session.sessionId,
                configId: "streaming",
                value: "true"
            ))
        )
        let setConfigResp = await service.handle(setConfigReq)
        let setConfigResult = try ACPCodec.decodeResult(setConfigResp.result, as: ACPSessionSetConfigOptionResult.self)
        XCTAssertEqual(setConfigResult.configOptions.first?.id, "streaming")
        XCTAssertEqual(setConfigResult.configOptions.first?.type, .boolean)
        XCTAssertEqual(setConfigResult.configOptions.first?.currentValue, "true")
    }

    func testSetModelUpdatesCurrentModelAndLoadReflectsChange() async throws {
        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: EchoTestClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(loadSession: true),
            notificationSink: { _ in }
        )

        let newReq = JSONRPCRequest(
            id: .int(120),
            method: ACPMethods.sessionNew,
            params: try ACPCodec.encodeParams(ACPSessionNewParams(cwd: "/tmp"))
        )
        let newResp = await service.handle(newReq)
        let session = try ACPCodec.decodeResult(newResp.result, as: ACPSessionNewResult.self)
        XCTAssertEqual(session.models?.currentModelId, "default")

        let setModelReq = JSONRPCRequest(
            id: .int(121),
            method: ACPMethods.sessionSetModel,
            params: try ACPCodec.encodeParams(ACPSessionSetModelParams(sessionId: session.sessionId, modelId: "gpt-5"))
        )
        let setModelResp = await service.handle(setModelReq)
        XCTAssertNil(setModelResp.error)

        let loadReq = JSONRPCRequest(
            id: .int(122),
            method: ACPMethods.sessionLoad,
            params: try ACPCodec.encodeParams(ACPSessionLoadParams(sessionId: session.sessionId, cwd: "/tmp"))
        )
        let loadResp = await service.handle(loadReq)
        let load = try ACPCodec.decodeResult(loadResp.result, as: ACPSessionLoadResult.self)
        XCTAssertEqual(load.models?.currentModelId, "gpt-5")
    }

    func testListResumeAndForkRequiresCapabilities() async throws {
        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: EchoTestClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(loadSession: true),
            notificationSink: { _ in }
        )

        let listResp = await service.handle(.init(id: .int(130), method: ACPMethods.sessionList, params: try ACPCodec.encodeParams(ACPSessionListParams())))
        XCTAssertEqual(listResp.error?.code, JSONRPCErrorCode.methodNotFound)

        let resumeResp = await service.handle(.init(
            id: .int(131),
            method: ACPMethods.sessionResume,
            params: try ACPCodec.encodeParams(ACPSessionResumeParams(sessionId: "sess_x", cwd: "/tmp"))
        ))
        XCTAssertEqual(resumeResp.error?.code, JSONRPCErrorCode.methodNotFound)

        let forkResp = await service.handle(.init(
            id: .int(132),
            method: ACPMethods.sessionFork,
            params: try ACPCodec.encodeParams(ACPSessionForkParams(sessionId: "sess_x", cwd: "/tmp"))
        ))
        XCTAssertEqual(forkResp.error?.code, JSONRPCErrorCode.methodNotFound)
    }

    func testListResumeAndForkWhenCapabilitiesEnabled() async throws {
        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: EchoTestClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(
                sessionCapabilities: .init(list: .init(), resume: .init(), fork: .init()),
                loadSession: true
            ),
            notificationSink: { _ in }
        )

        let newReq = JSONRPCRequest(
            id: .int(140),
            method: ACPMethods.sessionNew,
            params: try ACPCodec.encodeParams(ACPSessionNewParams(cwd: "/tmp/origin"))
        )
        let newResp = await service.handle(newReq)
        let newSession = try ACPCodec.decodeResult(newResp.result, as: ACPSessionNewResult.self)

        let listResp = await service.handle(.init(
            id: .int(141),
            method: ACPMethods.sessionList,
            params: try ACPCodec.encodeParams(ACPSessionListParams())
        ))
        let list = try ACPCodec.decodeResult(listResp.result, as: ACPSessionListResult.self)
        XCTAssertTrue(list.sessions.contains(where: { $0.sessionId == newSession.sessionId }))

        let resumeResp = await service.handle(.init(
            id: .int(142),
            method: ACPMethods.sessionResume,
            params: try ACPCodec.encodeParams(ACPSessionResumeParams(sessionId: newSession.sessionId, cwd: "/tmp/resumed"))
        ))
        let resumed = try ACPCodec.decodeResult(resumeResp.result, as: ACPSessionResumeResult.self)
        XCTAssertEqual(resumed.modes?.currentModeId, "default")

        let forkResp = await service.handle(.init(
            id: .int(143),
            method: ACPMethods.sessionFork,
            params: try ACPCodec.encodeParams(ACPSessionForkParams(sessionId: newSession.sessionId, cwd: "/tmp/forked"))
        ))
        let forked = try ACPCodec.decodeResult(forkResp.result, as: ACPSessionForkResult.self)
        XCTAssertNotEqual(forked.sessionId, newSession.sessionId)
        XCTAssertEqual(forked.models?.currentModelId, "default")
    }

    func testForkCopiesSessionStateAndKeepsIsolation() async throws {
        let notifications = NotificationBox()
        let service = ACPAgentService(
            sessionFactory: { ForkStateSession() },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(
                sessionCapabilities: .init(fork: .init()),
                loadSession: true
            ),
            notificationSink: { n in await notifications.append(n) }
        )

        let newResp = await service.handle(JSONRPCRequest(
            id: .int(1440),
            method: ACPMethods.sessionNew,
            params: try ACPCodec.encodeParams(ACPSessionNewParams(cwd: "/tmp/origin"))
        ))
        let origin = try ACPCodec.decodeResult(newResp.result, as: ACPSessionNewResult.self)

        _ = await service.handle(JSONRPCRequest(
            id: .int(1441),
            method: ACPMethods.sessionPrompt,
            params: try ACPCodec.encodeParams(ACPSessionPromptParams(sessionId: origin.sessionId, prompt: [.text("alpha")]))
        ))

        let forkResp = await service.handle(JSONRPCRequest(
            id: .int(1442),
            method: ACPMethods.sessionFork,
            params: try ACPCodec.encodeParams(ACPSessionForkParams(sessionId: origin.sessionId, cwd: "/tmp/forked"))
        ))
        let forked = try ACPCodec.decodeResult(forkResp.result, as: ACPSessionForkResult.self)

        _ = await service.handle(JSONRPCRequest(
            id: .int(1443),
            method: ACPMethods.sessionPrompt,
            params: try ACPCodec.encodeParams(ACPSessionPromptParams(sessionId: forked.sessionId, prompt: [.text("beta")]))
        ))
        _ = await service.handle(JSONRPCRequest(
            id: .int(1444),
            method: ACPMethods.sessionPrompt,
            params: try ACPCodec.encodeParams(ACPSessionPromptParams(sessionId: origin.sessionId, prompt: [.text("gamma")]))
        ))

        let updates: [ACPSessionUpdateParams] = try await notifications.snapshot()
            .map { try ACPCodec.decodeParams($0.params, as: ACPSessionUpdateParams.self) }

        let forkTexts = updates
            .filter { $0.sessionId == forked.sessionId && $0.update.sessionUpdate == .agentMessageChunk }
            .compactMap { $0.update.content?.text }
        let originTexts = updates
            .filter { $0.sessionId == origin.sessionId && $0.update.sessionUpdate == .agentMessageChunk }
            .compactMap { $0.update.content?.text }

        XCTAssertTrue(forkTexts.contains(where: { $0.contains("alpha,beta") }))
        XCTAssertTrue(originTexts.contains(where: { $0.contains("alpha,gamma") }))
        XCTAssertFalse(originTexts.contains(where: { $0.contains("alpha,beta") }))
    }

    func testSessionListSupportsCursorPagination() async throws {
        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: EchoTestClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(
                sessionCapabilities: .init(list: .init(), resume: .init(), fork: .init()),
                loadSession: true
            ),
            options: .init(sessionListPageSize: 2),
            notificationSink: { _ in }
        )

        var created: [String] = []
        for idx in 0..<3 {
            let newResp = await service.handle(JSONRPCRequest(
                id: .int(150 + idx),
                method: ACPMethods.sessionNew,
                params: try ACPCodec.encodeParams(ACPSessionNewParams(cwd: "/tmp/page-\(idx)"))
            ))
            let session = try ACPCodec.decodeResult(newResp.result, as: ACPSessionNewResult.self)
            created.append(session.sessionId)
        }

        let firstResp = await service.handle(JSONRPCRequest(
            id: .int(160),
            method: ACPMethods.sessionList,
            params: try ACPCodec.encodeParams(ACPSessionListParams())
        ))
        let first = try ACPCodec.decodeResult(firstResp.result, as: ACPSessionListResult.self)
        XCTAssertEqual(first.sessions.count, 2)
        XCTAssertNotNil(first.nextCursor)

        let secondResp = await service.handle(JSONRPCRequest(
            id: .int(161),
            method: ACPMethods.sessionList,
            params: try ACPCodec.encodeParams(ACPSessionListParams(cursor: first.nextCursor))
        ))
        let second = try ACPCodec.decodeResult(secondResp.result, as: ACPSessionListResult.self)
        XCTAssertEqual(second.sessions.count, 1)
        XCTAssertNil(second.nextCursor)

        let listed = Set((first.sessions + second.sessions).map { $0.sessionId })
        XCTAssertEqual(listed, Set(created))
    }

    func testSessionListIncludesParentSessionIdForForkedSession() async throws {
        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: EchoTestClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(
                sessionCapabilities: .init(list: .init(), fork: .init()),
                loadSession: true
            ),
            notificationSink: { _ in }
        )

        let newResp = await service.handle(JSONRPCRequest(
            id: .int(1660),
            method: ACPMethods.sessionNew,
            params: try ACPCodec.encodeParams(ACPSessionNewParams(cwd: "/tmp/parent"))
        ))
        let origin = try ACPCodec.decodeResult(newResp.result, as: ACPSessionNewResult.self)

        _ = await service.handle(JSONRPCRequest(
            id: .int(1661),
            method: ACPMethods.sessionFork,
            params: try ACPCodec.encodeParams(ACPSessionForkParams(sessionId: origin.sessionId, cwd: "/tmp/child"))
        ))

        let listResp = await service.handle(JSONRPCRequest(
            id: .int(1662),
            method: ACPMethods.sessionList,
            params: try ACPCodec.encodeParams(ACPSessionListParams())
        ))
        let list = try ACPCodec.decodeResult(listResp.result, as: ACPSessionListResult.self)
        let forked = try XCTUnwrap(list.sessions.first(where: { $0.parentSessionId == origin.sessionId }))
        XCTAssertEqual(forked.parentSessionId, origin.sessionId)
    }

    func testSessionExportRequiresCapability() async throws {
        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: EchoTestClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(sessionCapabilities: .init(), loadSession: true),
            notificationSink: { _ in }
        )

        let resp = await service.handle(JSONRPCRequest(
            id: .int(1663),
            method: ACPMethods.sessionExport,
            params: try ACPCodec.encodeParams(ACPSessionExportParams(sessionId: "sess_x"))
        ))
        XCTAssertEqual(resp.error?.code, JSONRPCErrorCode.methodNotFound)
    }

    func testSessionExportReturnsJSONLContent() async throws {
        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: EchoTestClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(
                sessionCapabilities: .init(export: .init()),
                loadSession: true
            ),
            notificationSink: { _ in }
        )

        let newResp = await service.handle(JSONRPCRequest(
            id: .int(1664),
            method: ACPMethods.sessionNew,
            params: try ACPCodec.encodeParams(ACPSessionNewParams(cwd: "/tmp/export"))
        ))
        let session = try ACPCodec.decodeResult(newResp.result, as: ACPSessionNewResult.self)

        _ = await service.handle(JSONRPCRequest(
            id: .int(1665),
            method: ACPMethods.sessionPrompt,
            params: try ACPCodec.encodeParams(ACPSessionPromptParams(sessionId: session.sessionId, prompt: [.text("hello export")]))
        ))

        let exportResp = await service.handle(JSONRPCRequest(
            id: .int(1666),
            method: ACPMethods.sessionExport,
            params: try ACPCodec.encodeParams(ACPSessionExportParams(sessionId: session.sessionId))
        ))
        let exported = try ACPCodec.decodeResult(exportResp.result, as: ACPSessionExportResult.self)
        XCTAssertEqual(exported.sessionId, session.sessionId)
        XCTAssertEqual(exported.format, .jsonl)
        XCTAssertEqual(exported.mimeType, "application/x-ndjson")
        XCTAssertTrue(exported.content.contains("\"type\":\"session\""))
        XCTAssertTrue(exported.content.contains("\"message\""))
    }

    func testSessionListInvalidCursorReturnsInvalidParams() async throws {
        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: EchoTestClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(
                sessionCapabilities: .init(list: .init()),
                loadSession: true
            ),
            notificationSink: { _ in }
        )

        _ = await service.handle(JSONRPCRequest(
            id: .int(170),
            method: ACPMethods.sessionNew,
            params: try ACPCodec.encodeParams(ACPSessionNewParams(cwd: "/tmp"))
        ))

        let resp = await service.handle(JSONRPCRequest(
            id: .int(171),
            method: ACPMethods.sessionList,
            params: try ACPCodec.encodeParams(ACPSessionListParams(cursor: "bad-cursor"))
        ))
        XCTAssertEqual(resp.error?.code, JSONRPCErrorCode.invalidParams)
    }

    func testSessionDeleteRequiresCapability() async throws {
        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: EchoTestClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(sessionCapabilities: .init(list: .init()), loadSession: true),
            notificationSink: { _ in }
        )

        let resp = await service.handle(JSONRPCRequest(
            id: .int(180),
            method: ACPMethods.sessionDelete,
            params: try ACPCodec.encodeParams(ACPSessionDeleteParams(sessionId: "sess_x"))
        ))
        XCTAssertEqual(resp.error?.code, JSONRPCErrorCode.methodNotFound)
    }

    func testSessionDeleteRemovesFromListAndIsIdempotent() async throws {
        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: EchoTestClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(
                sessionCapabilities: .init(list: .init(), delete: .init()),
                loadSession: true
            ),
            notificationSink: { _ in }
        )

        let newResp = await service.handle(JSONRPCRequest(
            id: .int(181),
            method: ACPMethods.sessionNew,
            params: try ACPCodec.encodeParams(ACPSessionNewParams(cwd: "/tmp/delete"))
        ))
        let session = try ACPCodec.decodeResult(newResp.result, as: ACPSessionNewResult.self)

        let deleteResp = await service.handle(JSONRPCRequest(
            id: .int(182),
            method: ACPMethods.sessionDelete,
            params: try ACPCodec.encodeParams(ACPSessionDeleteParams(sessionId: session.sessionId))
        ))
        XCTAssertNil(deleteResp.error)

        let listResp = await service.handle(JSONRPCRequest(
            id: .int(183),
            method: ACPMethods.sessionList,
            params: try ACPCodec.encodeParams(ACPSessionListParams())
        ))
        let list = try ACPCodec.decodeResult(listResp.result, as: ACPSessionListResult.self)
        XCTAssertFalse(list.sessions.contains(where: { $0.sessionId == session.sessionId }))

        let secondDelete = await service.handle(JSONRPCRequest(
            id: .int(184),
            method: ACPMethods.sessionDelete,
            params: try ACPCodec.encodeParams(ACPSessionDeleteParams(sessionId: session.sessionId))
        ))
        XCTAssertNil(secondDelete.error)
    }

    func testPromptEmitsSessionInfoUpdateAfterAutoTitleGenerated() async throws {
        let notifications = NotificationBox()
        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: EchoTestClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(loadSession: true),
            options: .init(autoSessionInfoUpdateOnFirstPrompt: true),
            notificationSink: { n in await notifications.append(n) }
        )

        let newResp = await service.handle(JSONRPCRequest(
            id: .int(185),
            method: ACPMethods.sessionNew,
            params: try ACPCodec.encodeParams(ACPSessionNewParams(cwd: "/tmp/info"))
        ))
        let session = try ACPCodec.decodeResult(newResp.result, as: ACPSessionNewResult.self)

        let promptResp = await service.handle(JSONRPCRequest(
            id: .int(186),
            method: ACPMethods.sessionPrompt,
            params: try ACPCodec.encodeParams(
                ACPSessionPromptParams(sessionId: session.sessionId, prompt: [.text("Debug authentication timeout and retry")])
            )
        ))
        XCTAssertNil(promptResp.error)

        let notificationsList = await notifications.snapshot()
        let updates: [ACPSessionUpdateParams] = try notificationsList
            .map { try ACPCodec.decodeParams($0.params, as: ACPSessionUpdateParams.self) }
        let infoUpdate = updates.first { $0.update.sessionUpdate == .sessionInfoUpdate }
        XCTAssertNotNil(infoUpdate)
        XCTAssertFalse((infoUpdate?.update.sessionInfoUpdate?.title ?? "").isEmpty)
    }
}

private actor NotificationBox {
    private var values: [JSONRPCNotification] = []
    func append(_ value: JSONRPCNotification) {
        values.append(value)
    }
    func snapshot() -> [JSONRPCNotification] { values }
}

private actor TelemetryBox {
    private var values: [ACPAgentTelemetryEvent] = []

    func append(_ value: ACPAgentTelemetryEvent) {
        values.append(value)
    }

    func snapshot() -> [ACPAgentTelemetryEvent] {
        values
    }
}

private struct EchoTestClient: SKILanguageModelClient {
    func respond(_ body: ChatRequestBody) async throws -> sending SKIResponse<ChatResponseBody> {
        let text = body.messages.compactMap { message -> String? in
            if case .user(let c, _) = message, case .text(let t) = c { return t }
            return nil
        }.joined(separator: "\n")

        let payload = """
        {
          "choices": [
            {
              "finish_reason": "stop",
              "message": {
                "content": "ok: \(text)",
                "role": "assistant"
              }
            }
          ],
          "created": 0,
          "model": "test"
        }
        """

        return try SKIResponse<ChatResponseBody>(
            httpResponse: .init(status: .ok),
            data: Data(payload.utf8)
        )
    }
}

private struct HistoryEchoClient: SKILanguageModelClient {
    func respond(_ body: ChatRequestBody) async throws -> sending SKIResponse<ChatResponseBody> {
        var lines: [String] = []
        for message in body.messages {
            switch message {
            case .system:
                continue
            case .developer:
                continue
            case .user(let content, _):
                if case .text(let text) = content {
                    lines.append("user:\(text)")
                }
            case .assistant(let content, _, _, _):
                if case .text(let text) = content {
                    lines.append("assistant:\(text)")
                }
            case .tool:
                continue
            }
        }
        let text = lines.joined(separator: " | ")

        let payload = """
        {
          "choices": [
            {
              "finish_reason": "stop",
              "message": {
                "content": "ok-history: \(text)",
                "role": "assistant"
              }
            }
          ],
          "created": 0,
          "model": "test"
        }
        """

        return try SKIResponse<ChatResponseBody>(
            httpResponse: .init(status: .ok),
            data: Data(payload.utf8)
        )
    }
}

private struct SlowCancellableClient: SKILanguageModelClient {
    func respond(_ body: ChatRequestBody) async throws -> sending SKIResponse<ChatResponseBody> {
        _ = body
        try await Task.sleep(nanoseconds: 400_000_000)
        try Task.checkCancellation()

        let payload = """
        {
          "choices": [
            {
              "finish_reason": "stop",
              "message": {
                "content": "slow",
                "role": "assistant"
              }
            }
          ],
          "created": 0,
          "model": "test"
        }
        """

        return try SKIResponse<ChatResponseBody>(
            httpResponse: .init(status: .ok),
            data: Data(payload.utf8)
        )
    }
}

private actor RetryOnceCounter {
    private var count: Int = 0

    func reset() {
        count = 0
    }

    func nextAttempt() -> Int {
        defer { count += 1 }
        return count
    }
}

private struct RetryOnceClient: SKILanguageModelClient {
    private static let counter = RetryOnceCounter()

    static func resetCounter() async {
        await counter.reset()
    }

    func respond(_ body: ChatRequestBody) async throws -> sending SKIResponse<ChatResponseBody> {
        _ = body
        let current = await Self.counter.nextAttempt()
        if current == 0 {
            throw NSError(domain: "RetryOnceClient", code: 1, userInfo: [NSLocalizedDescriptionKey: "transient"])
        }

        let payload = """
        {
          "choices": [
            {
              "finish_reason": "stop",
              "message": {
                "content": "retry-ok",
                "role": "assistant"
              }
            }
          ],
          "created": 0,
          "model": "test"
        }
        """

        return try SKIResponse<ChatResponseBody>(
            httpResponse: .init(status: .ok),
            data: Data(payload.utf8)
        )
    }
}

private struct AlwaysFailClient: SKILanguageModelClient {
    func respond(_ body: ChatRequestBody) async throws -> sending SKIResponse<ChatResponseBody> {
        _ = body
        throw NSError(domain: "AlwaysFailClient", code: 2, userInfo: [NSLocalizedDescriptionKey: "permanent"])
    }
}

private actor PromptCallCounter {
    private(set) var count: Int = 0
    func increment() { count += 1 }
}

private actor ForkStateSession: ACPAgentSession {
    private var prompts: [String] = []

    func prompt(_ text: String) async throws -> String {
        prompts.append(text)
        return "history:\(prompts.joined(separator: ","))"
    }

    func snapshotEntries() async throws -> [SKITranscript.Entry] {
        prompts.map { .message(.user(content: .text($0))) }
    }

    func restoreEntries(_ entries: [SKITranscript.Entry]) async throws {
        prompts = entries.compactMap { entry in
            guard case .message(let message) = entry,
                  case .user(let content, _) = message,
                  case .text(let text) = content
            else { return nil }
            return text
        }
    }
}

private struct CountingEchoClient: SKILanguageModelClient {
    let counter: PromptCallCounter

    func respond(_ body: ChatRequestBody) async throws -> sending SKIResponse<ChatResponseBody> {
        _ = body
        await counter.increment()
        let payload = """
        {
          "choices": [
            {
              "finish_reason": "stop",
              "message": {
                "content": "counting",
                "role": "assistant"
              }
            }
          ],
          "created": 0,
          "model": "test"
        }
        """

        return try SKIResponse<ChatResponseBody>(
            httpResponse: .init(status: .ok),
            data: Data(payload.utf8)
        )
    }
}
