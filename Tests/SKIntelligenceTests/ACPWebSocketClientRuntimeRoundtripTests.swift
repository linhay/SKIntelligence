import Foundation
import XCTest
@testable import SKIACP
@testable import SKIACPAgent
@testable import SKIACPClient
@testable import SKIACPTransport
@testable import SKIJSONRPC
@testable import SKIntelligence

final class ACPWebSocketClientRuntimeRoundtripTests: XCTestCase {
    func testAgentCanInvokeClientFSAndTerminalRuntimesOverWebSocket() async throws {
        let (serverTransport, port) = try await ACPWebSocketTestHarness.makeServerTransport()
        let inbox = WSRuntimeResponseInbox()

        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: EchoWSRuntimeClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(loadSession: true),
            notificationSink: { notification in
                try? await serverTransport.send(.notification(notification))
            }
        )

        let serverLoop = Task {
            while let message = try await serverTransport.receive() {
                switch message {
                case .request(let request):
                    let response = await service.handle(request)
                    try await serverTransport.send(.response(response))
                case .notification(let notification):
                    await service.handleCancel(notification)
                case .response(let response):
                    await inbox.push(response)
                }
            }
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("acp-ws-runtime-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("input.txt")
        try "line-1\nline-2\nline-3".write(to: source, atomically: true, encoding: .utf8)

        let endpoint = URL(string: "ws://127.0.0.1:\(port)")!
        let client = ACPClientService(transport: WebSocketClientTransport(endpoint: endpoint))
        await client.installRuntimes(
            filesystem: ACPLocalFilesystemRuntime(policy: .rooted(root)),
            terminal: ACPProcessTerminalRuntime()
        )

        try await client.connect()
        defer {
            serverLoop.cancel()
            Task {
                await client.close()
                await serverTransport.close()
            }
        }

        _ = try await client.initialize(
            .init(
                protocolVersion: 1,
                clientCapabilities: .init(
                    fs: .init(readTextFile: true, writeTextFile: true),
                    terminal: true
                ),
                clientInfo: .init(name: "runtime-client", version: "1.0.0")
            )
        )
        let session = try await client.newSession(.init(cwd: root.path))

        let fsReadID: JSONRPCID = .string("fs-read-1")
        try await serverTransport.send(.request(.init(
            id: fsReadID,
            method: ACPMethods.fsReadTextFile,
            params: try ACPCodec.encodeParams(
                ACPReadTextFileParams(sessionId: session.sessionId, path: source.path, line: 2, limit: 1)
            )
        )))
        let fsReadResp = try await waitResponse(inbox: inbox, id: fsReadID)
        XCTAssertNil(fsReadResp.error)
        let fsReadResult = try ACPCodec.decodeResult(fsReadResp.result, as: ACPReadTextFileResult.self)
        XCTAssertEqual(fsReadResult.content, "line-2")

        let target = root.appendingPathComponent("written.txt")
        let fsWriteID: JSONRPCID = .string("fs-write-1")
        try await serverTransport.send(.request(.init(
            id: fsWriteID,
            method: ACPMethods.fsWriteTextFile,
            params: try ACPCodec.encodeParams(
                ACPWriteTextFileParams(sessionId: session.sessionId, path: target.path, content: "hello-ws")
            )
        )))
        let fsWriteResp = try await waitResponse(inbox: inbox, id: fsWriteID)
        XCTAssertNil(fsWriteResp.error)
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "hello-ws")

        let createID: JSONRPCID = .string("term-create-1")
        try await serverTransport.send(.request(.init(
            id: createID,
            method: ACPMethods.terminalCreate,
            params: try ACPCodec.encodeParams(
                ACPTerminalCreateParams(
                    sessionId: session.sessionId,
                    command: "/bin/sh",
                    args: ["-c", "printf 'ws-terminal'"]
                )
            )
        )))
        let createResp = try await waitResponse(inbox: inbox, id: createID)
        XCTAssertNil(createResp.error)
        let createResult = try ACPCodec.decodeResult(createResp.result, as: ACPTerminalCreateResult.self)

        let waitID: JSONRPCID = .string("term-wait-1")
        try await serverTransport.send(.request(.init(
            id: waitID,
            method: ACPMethods.terminalWaitForExit,
            params: try ACPCodec.encodeParams(
                ACPTerminalRefParams(sessionId: session.sessionId, terminalId: createResult.terminalId)
            )
        )))
        let waitResp = try await waitResponse(inbox: inbox, id: waitID)
        XCTAssertNil(waitResp.error)
        let waitResult = try ACPCodec.decodeResult(waitResp.result, as: ACPTerminalWaitForExitResult.self)
        XCTAssertEqual(waitResult.exitCode, 0)

        let outputID: JSONRPCID = .string("term-output-1")
        try await serverTransport.send(.request(.init(
            id: outputID,
            method: ACPMethods.terminalOutput,
            params: try ACPCodec.encodeParams(
                ACPTerminalRefParams(sessionId: session.sessionId, terminalId: createResult.terminalId)
            )
        )))
        let outputResp = try await waitResponse(inbox: inbox, id: outputID)
        XCTAssertNil(outputResp.error)
        let outputResult = try ACPCodec.decodeResult(outputResp.result, as: ACPTerminalOutputResult.self)
        XCTAssertTrue(outputResult.output.contains("ws-terminal"))
        XCTAssertEqual(outputResult.exitStatus?.exitCode, 0)

        let releaseID: JSONRPCID = .string("term-release-1")
        try await serverTransport.send(.request(.init(
            id: releaseID,
            method: ACPMethods.terminalRelease,
            params: try ACPCodec.encodeParams(
                ACPTerminalRefParams(sessionId: session.sessionId, terminalId: createResult.terminalId)
            )
        )))
        let releaseResp = try await waitResponse(inbox: inbox, id: releaseID)
        XCTAssertNil(releaseResp.error)
    }

    func testKilledTerminalCanStillOutputUntilReleaseOverWebSocket() async throws {
        let (serverTransport, port) = try await ACPWebSocketTestHarness.makeServerTransport()
        let inbox = WSRuntimeResponseInbox()

        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: EchoWSRuntimeClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(loadSession: true),
            notificationSink: { notification in
                try? await serverTransport.send(.notification(notification))
            }
        )

        let serverLoop = Task {
            while let message = try await serverTransport.receive() {
                switch message {
                case .request(let request):
                    let response = await service.handle(request)
                    try await serverTransport.send(.response(response))
                case .notification(let notification):
                    await service.handleCancel(notification)
                case .response(let response):
                    await inbox.push(response)
                }
            }
        }

        let endpoint = URL(string: "ws://127.0.0.1:\(port)")!
        let client = ACPClientService(transport: WebSocketClientTransport(endpoint: endpoint))
        await client.installRuntimes(
            filesystem: ACPLocalFilesystemRuntime(),
            terminal: ACPProcessTerminalRuntime()
        )

        try await client.connect()
        defer {
            serverLoop.cancel()
            Task {
                await client.close()
                await serverTransport.close()
            }
        }

        _ = try await client.initialize(
            .init(
                protocolVersion: 1,
                clientCapabilities: .init(fs: .init(), terminal: true),
                clientInfo: .init(name: "runtime-client", version: "1.0.0")
            )
        )
        let session = try await client.newSession(.init(cwd: "/tmp"))

        let createID: JSONRPCID = .string("kill-create")
        try await serverTransport.send(.request(.init(
            id: createID,
            method: ACPMethods.terminalCreate,
            params: try ACPCodec.encodeParams(
                ACPTerminalCreateParams(
                    sessionId: session.sessionId,
                    command: "/bin/sh",
                    args: ["-c", "echo killed-output; sleep 5"]
                )
            )
        )))
        let createResp = try await waitResponse(inbox: inbox, id: createID)
        XCTAssertNil(createResp.error)
        let createResult = try ACPCodec.decodeResult(createResp.result, as: ACPTerminalCreateResult.self)

        try await Task.sleep(nanoseconds: 150_000_000)

        let killID: JSONRPCID = .string("kill-now")
        try await serverTransport.send(.request(.init(
            id: killID,
            method: ACPMethods.terminalKill,
            params: try ACPCodec.encodeParams(
                ACPTerminalRefParams(sessionId: session.sessionId, terminalId: createResult.terminalId)
            )
        )))
        let killResp = try await waitResponse(inbox: inbox, id: killID)
        XCTAssertNil(killResp.error)

        let waitID: JSONRPCID = .string("kill-wait")
        try await serverTransport.send(.request(.init(
            id: waitID,
            method: ACPMethods.terminalWaitForExit,
            params: try ACPCodec.encodeParams(
                ACPTerminalRefParams(sessionId: session.sessionId, terminalId: createResult.terminalId)
            )
        )))
        let waitResp = try await waitResponse(inbox: inbox, id: waitID)
        XCTAssertNil(waitResp.error)

        let outputID: JSONRPCID = .string("kill-output")
        try await serverTransport.send(.request(.init(
            id: outputID,
            method: ACPMethods.terminalOutput,
            params: try ACPCodec.encodeParams(
                ACPTerminalRefParams(sessionId: session.sessionId, terminalId: createResult.terminalId)
            )
        )))
        let outputResp = try await waitResponse(inbox: inbox, id: outputID)
        XCTAssertNil(outputResp.error)
        let outputResult = try ACPCodec.decodeResult(outputResp.result, as: ACPTerminalOutputResult.self)
        XCTAssertTrue(outputResult.output.contains("killed-output"))

        let releaseID: JSONRPCID = .string("kill-release")
        try await serverTransport.send(.request(.init(
            id: releaseID,
            method: ACPMethods.terminalRelease,
            params: try ACPCodec.encodeParams(
                ACPTerminalRefParams(sessionId: session.sessionId, terminalId: createResult.terminalId)
            )
        )))
        _ = try await waitResponse(inbox: inbox, id: releaseID)

        let afterReleaseOutputID: JSONRPCID = .string("kill-output-after-release")
        try await serverTransport.send(.request(.init(
            id: afterReleaseOutputID,
            method: ACPMethods.terminalOutput,
            params: try ACPCodec.encodeParams(
                ACPTerminalRefParams(sessionId: session.sessionId, terminalId: createResult.terminalId)
            )
        )))
        let afterReleaseOutputResp = try await waitResponse(inbox: inbox, id: afterReleaseOutputID)
        XCTAssertEqual(afterReleaseOutputResp.error?.code, JSONRPCErrorCode.internalError)
    }

    private func waitResponse(
        inbox: WSRuntimeResponseInbox,
        id: JSONRPCID,
        timeoutNanoseconds: UInt64 = 2_000_000_000
    ) async throws -> JSONRPCResponse {
        try await withThrowingTaskGroup(of: JSONRPCResponse.self) { group in
            group.addTask {
                try await inbox.awaitResponse(id: id)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                throw NSError(
                    domain: "ACPWebSocketClientRuntimeRoundtripTests",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for response: \(id)"]
                )
            }

            let response = try await group.next()!
            group.cancelAll()
            return response
        }
    }
}

private actor WSRuntimeResponseInbox {
    private var buffered: [JSONRPCID: JSONRPCResponse] = [:]
    private var waiters: [JSONRPCID: CheckedContinuation<JSONRPCResponse, Error>] = [:]

    func push(_ response: JSONRPCResponse) {
        if let continuation = waiters.removeValue(forKey: response.id) {
            continuation.resume(returning: response)
            return
        }
        buffered[response.id] = response
    }

    func awaitResponse(id: JSONRPCID) async throws -> JSONRPCResponse {
        if let response = buffered.removeValue(forKey: id) {
            return response
        }

        return try await withCheckedThrowingContinuation { continuation in
            waiters[id] = continuation
        }
    }
}

private struct EchoWSRuntimeClient: SKILanguageModelClient {
    func respond(_ body: ChatRequestBody) async throws -> sending SKIResponse<ChatResponseBody> {
        _ = body
        let payload = """
        {
          "choices": [
            {
              "finish_reason": "stop",
              "message": {
                "content": "ok",
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
