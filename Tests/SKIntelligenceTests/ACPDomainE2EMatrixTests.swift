import Foundation
 import STJSON
import XCTest
@testable import SKIACP
@testable import SKIACPAgent
@testable import SKIACPClient
@testable import SKIACPTransport
@testable import SKIntelligence

final class ACPDomainE2EMatrixTests: XCTestCase {
    func testInitializeAuthenticateContractConsistentBetweenStdioAndWebSocket() async throws {
        let stdio = try await runInitializeAuthenticateScenario(transport: .stdioInProcess)
        let ws = try await runInitializeAuthenticateScenario(transport: .wsInProcess)

        XCTAssertEqual(stdio.protocolVersion, 1)
        XCTAssertEqual(ws.protocolVersion, 1)
        XCTAssertEqual(stdio.authMethodIDs, ["token"])
        XCTAssertEqual(ws.authMethodIDs, ["token"])
        XCTAssertEqual(stdio, ws)
    }

    func testSessionListContractConsistentBetweenStdioAndWebSocket() async throws {
        let stdio = try await runSessionListScenario(transport: .stdioInProcess)
        let ws = try await runSessionListScenario(transport: .wsInProcess)

        XCTAssertEqual(stdio.createdCount, 3)
        XCTAssertEqual(ws.createdCount, 3)
        XCTAssertEqual(stdio.listedCount, 3)
        XCTAssertEqual(ws.listedCount, 3)
        XCTAssertEqual(stdio.uniqueIDsCount, 3)
        XCTAssertEqual(ws.uniqueIDsCount, 3)
        XCTAssertEqual(stdio, ws)
    }

    func testSetModelLoadContractConsistentBetweenStdioAndWebSocket() async throws {
        let stdio = try await runSetModelLoadScenario(transport: .stdioInProcess)
        let ws = try await runSetModelLoadScenario(transport: .wsInProcess)

        XCTAssertEqual(stdio.currentModelIdAfterLoad, "gpt-5")
        XCTAssertEqual(ws.currentModelIdAfterLoad, "gpt-5")
        XCTAssertTrue(stdio.availableModelsAfterLoad.contains("gpt-5"))
        XCTAssertTrue(ws.availableModelsAfterLoad.contains("gpt-5"))
        XCTAssertEqual(stdio, ws)
    }

    func testSessionCancelPromptContractConsistentBetweenStdioAndWebSocket() async throws {
        let stdio = try await runSessionCancelPromptScenario(transport: .stdioInProcess)
        let ws = try await runSessionCancelPromptScenario(transport: .wsInProcess)

        XCTAssertEqual(stdio, .cancelled)
        XCTAssertEqual(ws, .cancelled)
    }

    func testSessionStopPromptContractConsistentBetweenStdioAndWebSocket() async throws {
        let stdio = try await runSessionStopPromptScenario(transport: .stdioInProcess)
        let ws = try await runSessionStopPromptScenario(transport: .wsInProcess)

        XCTAssertEqual(stdio, .cancelled)
        XCTAssertEqual(ws, .cancelled)
    }

    func testCancelRequestPromptContractConsistentBetweenStdioAndWebSocket() async throws {
        let stdio = try await runCancelRequestPromptScenario(transport: .stdioInProcess)
        let ws = try await runCancelRequestPromptScenario(transport: .wsInProcess)

        XCTAssertEqual(stdio, JSONRPCErrorCode.requestCancelled)
        XCTAssertEqual(ws, JSONRPCErrorCode.requestCancelled)
    }

    func testCancelRequestDuringPermissionContractConsistentBetweenStdioAndWebSocket() async throws {
        let stdio = try await runCancelRequestDuringPermissionScenario(transport: .stdioInProcess)
        let ws = try await runCancelRequestDuringPermissionScenario(transport: .wsInProcess)

        XCTAssertEqual(stdio, JSONRPCErrorCode.requestCancelled)
        XCTAssertEqual(ws, JSONRPCErrorCode.requestCancelled)
    }

    func testCancelRequestPromptWithStringRequestIDContractConsistentBetweenStdioAndWebSocket() async throws {
        let stdio = try await runCancelRequestPromptWithStringRequestIDScenario(transport: .stdioInProcess)
        let ws = try await runCancelRequestPromptWithStringRequestIDScenario(transport: .wsInProcess)

        XCTAssertEqual(stdio, JSONRPCErrorCode.requestCancelled)
        XCTAssertEqual(ws, JSONRPCErrorCode.requestCancelled)
    }

    func testPreCancelRequestPromptContractConsistentBetweenStdioAndWebSocket() async throws {
        let stdio = try await runPreCancelRequestPromptScenario(transport: .stdioInProcess)
        let ws = try await runPreCancelRequestPromptScenario(transport: .wsInProcess)

        XCTAssertEqual(stdio.intPromptCodeFromStringCancel, JSONRPCErrorCode.requestCancelled)
        XCTAssertEqual(stdio.stringPromptCodeFromIntCancel, JSONRPCErrorCode.requestCancelled)
        XCTAssertEqual(ws.intPromptCodeFromStringCancel, JSONRPCErrorCode.requestCancelled)
        XCTAssertEqual(ws.stringPromptCodeFromIntCancel, JSONRPCErrorCode.requestCancelled)
        XCTAssertEqual(stdio, ws)
    }

    func testPermissionDeniedContractConsistentBetweenStdioAndWebSocket() async throws {
        let stdio = try await runPermissionDeniedScenario(
            transport: .stdioInProcess
        )
        let ws = try await runPermissionDeniedScenario(
            transport: .wsInProcess
        )

        XCTAssertEqual(stdio, .cancelled)
        XCTAssertEqual(ws, .cancelled)
    }

    func testForkLoadExportContractConsistentBetweenStdioAndWebSocket() async throws {
        let stdio = try await runForkLoadExportScenario(
            transport: .stdioInProcess
        )
        let ws = try await runForkLoadExportScenario(
            transport: .wsInProcess
        )

        XCTAssertEqual(stdio.stopReason, .endTurn)
        XCTAssertEqual(ws.stopReason, .endTurn)
        XCTAssertTrue(stdio.forkedSessionDifferent)
        XCTAssertTrue(ws.forkedSessionDifferent)
        XCTAssertTrue(stdio.originExportLooksValid)
        XCTAssertTrue(stdio.forkExportLooksValid)
        XCTAssertTrue(ws.originExportLooksValid)
        XCTAssertTrue(ws.forkExportLooksValid)
    }

    func testForkLoadExportContractStdioInProcess() async throws {
        let result = try await runForkLoadExportScenario(transport: .stdioInProcess)
        XCTAssertEqual(result.stopReason, .endTurn)
        XCTAssertTrue(result.forkedSessionDifferent)
        XCTAssertTrue(result.originExportLooksValid)
        XCTAssertTrue(result.forkExportLooksValid)
    }

    func testForkLoadExportContractWebSocketInProcess() async throws {
        let result = try await runForkLoadExportScenario(transport: .wsInProcess)
        XCTAssertEqual(result.stopReason, .endTurn)
        XCTAssertTrue(result.forkedSessionDifferent)
        XCTAssertTrue(result.originExportLooksValid)
        XCTAssertTrue(result.forkExportLooksValid)
    }

    func testForkPromptContractStdioInProcess() async throws {
        let result = try await runForkPromptScenario(transport: .stdioInProcess)
        XCTAssertTrue(result.contains("alpha"))
        XCTAssertTrue(result.contains("beta"))
    }

    func testForkPromptContractWebSocketInProcess() async throws {
        let result = try await runForkPromptScenario(transport: .wsInProcess)
        XCTAssertTrue(result.contains("alpha"))
        XCTAssertTrue(result.contains("beta"))
    }

    func testForkPromptContractConsistentBetweenStdioAndWebSocket() async throws {
        let stdio = try await runForkPromptScenario(transport: .stdioInProcess)
        let ws = try await runForkPromptScenario(transport: .wsInProcess)
        XCTAssertEqual(stdio, ws)
        XCTAssertTrue(stdio.contains("alpha"))
        XCTAssertTrue(stdio.contains("beta"))
    }

    func testRuntimeFSAndTerminalLifecycleContractConsistentBetweenStdioAndWebSocket() async throws {
        let stdio = try await runRuntimeFSAndTerminalLifecycleScenario(transport: .stdioInProcess)
        let ws = try await runRuntimeFSAndTerminalLifecycleScenario(transport: .wsInProcess)
        XCTAssertEqual(stdio, ws)
        XCTAssertEqual(stdio.fsReadContent, "line-2")
        XCTAssertEqual(stdio.writtenContent, "written-from-matrix")
        XCTAssertTrue(stdio.terminalOutputContainsToken)
        XCTAssertEqual(stdio.terminalExitCode, 0)
        XCTAssertEqual(stdio.outputAfterReleaseErrorCode, JSONRPCErrorCode.internalError)
    }

    func testRuntimeTerminalKillContractConsistentBetweenStdioAndWebSocket() async throws {
        let stdio = try await runRuntimeTerminalKillScenario(transport: .stdioInProcess)
        let ws = try await runRuntimeTerminalKillScenario(transport: .wsInProcess)
        XCTAssertEqual(stdio, ws)
        XCTAssertTrue(stdio.outputContainsKilledToken)
        XCTAssertEqual(stdio.outputAfterReleaseErrorCode, JSONRPCErrorCode.internalError)
    }
}

private extension ACPDomainE2EMatrixTests {
    enum MatrixAuthMode {
        case none
        case token
    }

    enum MatrixModelBehavior {
        case echo
        case slow
    }

    enum MatrixPermissionMode {
        case bridge
        case disabled
    }

    struct InitializeAuthResult: Equatable {
        let protocolVersion: Int
        let authMethodIDs: [String]
    }

    struct SessionListResult: Equatable {
        let createdCount: Int
        let listedCount: Int
        let uniqueIDsCount: Int
    }

    struct SetModelLoadResult: Equatable {
        let currentModelIdAfterLoad: String
        let availableModelsAfterLoad: [String]
    }

    enum MatrixTransport {
        case stdioInProcess
        case wsInProcess
    }

    struct ForkLoadExportResult: Equatable {
        let stopReason: ACPStopReason
        let forkedSessionDifferent: Bool
        let originExportLooksValid: Bool
        let forkExportLooksValid: Bool
    }

    struct PreCancelResult: Equatable {
        let intPromptCodeFromStringCancel: Int
        let stringPromptCodeFromIntCancel: Int
    }

    struct RuntimeLifecycleResult: Equatable {
        let fsReadContent: String
        let writtenContent: String
        let terminalOutputContainsToken: Bool
        let terminalExitCode: Int?
        let outputAfterReleaseErrorCode: Int
    }

    struct RuntimeKillResult: Equatable {
        let outputContainsKilledToken: Bool
        let outputAfterReleaseErrorCode: Int
    }

    func runPermissionDeniedScenario(transport: MatrixTransport) async throws -> ACPStopReason {
        try await withClient(transport: transport, allowPermission: false) { client in
            _ = try await client.initialize(.init(protocolVersion: 1))
            let session = try await client.newSession(.init(cwd: FileManager.default.currentDirectoryPath))
            let result = try await client.prompt(.init(sessionId: session.sessionId, prompt: [.text("permission check")]))
            return result.stopReason
        }
    }

    func runInitializeAuthenticateScenario(transport: MatrixTransport) async throws -> InitializeAuthResult {
        try await withClient(transport: transport, allowPermission: true, authMode: .token) { client in
            let initialize = try await client.initialize(.init(protocolVersion: 1))
            _ = try await client.authenticate(.init(methodId: "token"))
            return .init(
                protocolVersion: initialize.protocolVersion,
                authMethodIDs: initialize.authMethods.map(\.id)
            )
        }
    }

    func runSessionListScenario(transport: MatrixTransport) async throws -> SessionListResult {
        try await withClient(transport: transport, allowPermission: true) { client in
            _ = try await client.initialize(.init(protocolVersion: 1))

            var created: [String] = []
            for _ in 0..<3 {
                let session = try await client.newSession(.init(cwd: FileManager.default.currentDirectoryPath))
                created.append(session.sessionId)
            }

            var listed: [String] = []
            var cursor: String?
            repeat {
                let page = try await client.listSessions(.init(cursor: cursor))
                listed.append(contentsOf: page.sessions.map(\.sessionId))
                cursor = page.nextCursor
            } while cursor != nil

            return .init(
                createdCount: created.count,
                listedCount: listed.filter { created.contains($0) }.count,
                uniqueIDsCount: Set(listed.filter { created.contains($0) }).count
            )
        }
    }

    func runSetModelLoadScenario(transport: MatrixTransport) async throws -> SetModelLoadResult {
        try await withClient(transport: transport, allowPermission: true) { client in
            _ = try await client.initialize(.init(protocolVersion: 1))
            let session = try await client.newSession(.init(cwd: FileManager.default.currentDirectoryPath))
            _ = try await client.setModel(.init(sessionId: session.sessionId, modelId: "gpt-5"))
            try await client.loadSession(.init(sessionId: session.sessionId, cwd: FileManager.default.currentDirectoryPath))
            let resumed = try await client.resumeSession(.init(sessionId: session.sessionId, cwd: FileManager.default.currentDirectoryPath))
            let models = resumed.models?.availableModels.map(\.modelId) ?? []
            return .init(
                currentModelIdAfterLoad: resumed.models?.currentModelId ?? "",
                availableModelsAfterLoad: models.sorted()
            )
        }
    }

    func runSessionCancelPromptScenario(transport: MatrixTransport) async throws -> ACPStopReason {
        try await withClient(transport: transport, allowPermission: true, modelBehavior: .slow) { client in
            _ = try await client.initialize(.init(protocolVersion: 1))
            let session = try await client.newSession(.init(cwd: FileManager.default.currentDirectoryPath))

            let promptTask = Task {
                try await client.prompt(.init(sessionId: session.sessionId, prompt: [.text("cancel me")]))
            }

            try await Task.sleep(nanoseconds: 100_000_000)
            try await client.cancel(.init(sessionId: session.sessionId))

            let result = try await promptTask.value
            return result.stopReason
        }
    }

    func runSessionStopPromptScenario(transport: MatrixTransport) async throws -> ACPStopReason {
        try await withClient(transport: transport, allowPermission: true, modelBehavior: .slow) { client in
            _ = try await client.initialize(.init(protocolVersion: 1))
            let session = try await client.newSession(.init(cwd: FileManager.default.currentDirectoryPath))

            let promptTask = Task {
                try await client.prompt(.init(sessionId: session.sessionId, prompt: [.text("stop me")]))
            }

            try await Task.sleep(nanoseconds: 100_000_000)
            _ = try await client.stopSession(.init(sessionId: session.sessionId))

            let result = try await promptTask.value
            return result.stopReason
        }
    }

    func runCancelRequestPromptScenario(transport: MatrixTransport) async throws -> Int {
        let harness: InProcessMatrixHarness
        switch transport {
        case .stdioInProcess:
            harness = try await InProcessMatrixHarness.startStdio(
                modelBehavior: .slow,
                permissionMode: .disabled
            )
        case .wsInProcess:
            harness = try await InProcessMatrixHarness.startWebSocket(
                modelBehavior: .slow,
                permissionMode: .disabled
            )
        }
        defer { Task { await harness.stop() } }

        let transportClient = harness.clientTransport
        try await transportClient.connect()
        defer { Task { await transportClient.close() } }

        try await transportClient.send(.request(JSONRPC.Request(
            id: .int(1),
            method: ACPMethods.initialize,
            params: try ACPCodec.encodeParams(ACPInitializeParams(protocolVersion: 1))
        )))
        _ = try await expectResponse(id: .int(1), from: transportClient)

        try await transportClient.send(.request(JSONRPC.Request(
            id: .int(2),
            method: ACPMethods.sessionNew,
            params: try ACPCodec.encodeParams(ACPSessionNewParams(cwd: FileManager.default.currentDirectoryPath))
        )))
        let sessionNewResponse = try await expectResponse(id: .int(2), from: transportClient)
        guard let payload = sessionNewResponse.result else {
            XCTFail("Expected session/new result")
            return JSONRPCErrorCode.internalError
        }
        let sessionNew = try ACPCodec.decodeParams(payload, as: ACPSessionNewResult.self)

        try await transportClient.send(.request(JSONRPC.Request(
            id: .int(3),
            method: ACPMethods.sessionPrompt,
            params: try ACPCodec.encodeParams(ACPSessionPromptParams(
                sessionId: sessionNew.sessionId,
                prompt: [.text("cancel by protocol")]
            ))
        )))
        try await Task.sleep(nanoseconds: 100_000_000)
        try await transportClient.send(.notification(JSONRPC.Request(
            method: ACPMethods.cancelRequest,
            params: try ACPCodec.encodeParams(ACPCancelRequestParams(requestId: .int(3)))
        )))

        let promptResponse = try await expectResponse(id: .int(3), from: transportClient)
        return promptResponse.error?.code.value ?? JSONRPCErrorCode.internalError
    }

    func runCancelRequestDuringPermissionScenario(transport: MatrixTransport) async throws -> Int {
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
                let values = waiters
                waiters.removeAll(keepingCapacity: false)
                values.forEach { $0.resume() }
            }
        }

        let harness: InProcessMatrixHarness
        switch transport {
        case .stdioInProcess:
            harness = try await InProcessMatrixHarness.startStdio(
                modelBehavior: .echo,
                permissionMode: .bridge
            )
        case .wsInProcess:
            harness = try await InProcessMatrixHarness.startWebSocket(
                modelBehavior: .echo,
                permissionMode: .bridge
            )
        }
        defer { Task { await harness.stop() } }

        let gate = PermissionGate()
        let client = ACPClientService(
            transport: harness.clientTransport,
            requestTimeoutNanoseconds: 10_000_000_000
        )
        await client.setPermissionRequestHandler { _ in
            await gate.waitUntilReleased()
            return .init(outcome: .selected(.init(optionId: "allow_once")))
        }

        try await client.connect()
        defer { Task { await client.close() } }

        _ = try await client.initialize(.init(protocolVersion: 1))
        let session = try await client.newSession(.init(cwd: FileManager.default.currentDirectoryPath))

        let promptTask = Task<Int, Never> {
            do {
                _ = try await client.prompt(.init(sessionId: session.sessionId, prompt: [.text("cancel during permission")]))
                return JSONRPCErrorCode.internalError
            } catch let error as ACPClientServiceError {
                if case .rpcError(let code, _) = error {
                    return code
                }
                return JSONRPCErrorCode.internalError
            } catch {
                return JSONRPCErrorCode.internalError
            }
        }

        try await Task.sleep(nanoseconds: 30_000_000)
        try await client.cancelRequest(.init(requestId: .int(3)))
        await gate.release()

        return await promptTask.value
    }

    func runCancelRequestPromptWithStringRequestIDScenario(transport: MatrixTransport) async throws -> Int {
        let harness: InProcessMatrixHarness
        switch transport {
        case .stdioInProcess:
            harness = try await InProcessMatrixHarness.startStdio(
                modelBehavior: .slow,
                permissionMode: .disabled
            )
        case .wsInProcess:
            harness = try await InProcessMatrixHarness.startWebSocket(
                modelBehavior: .slow,
                permissionMode: .disabled
            )
        }
        defer { Task { await harness.stop() } }

        let transportClient = harness.clientTransport
        try await transportClient.connect()
        defer { Task { await transportClient.close() } }

        try await transportClient.send(.request(JSONRPC.Request(
            id: .string("init-1"),
            method: ACPMethods.initialize,
            params: try ACPCodec.encodeParams(ACPInitializeParams(protocolVersion: 1))
        )))
        _ = try await expectResponse(id: .string("init-1"), from: transportClient)

        try await transportClient.send(.request(JSONRPC.Request(
            id: .string("new-1"),
            method: ACPMethods.sessionNew,
            params: try ACPCodec.encodeParams(ACPSessionNewParams(cwd: FileManager.default.currentDirectoryPath))
        )))
        let sessionNewResponse = try await expectResponse(id: .string("new-1"), from: transportClient)
        guard let payload = sessionNewResponse.result else {
            XCTFail("Expected session/new result")
            return JSONRPCErrorCode.internalError
        }
        let sessionNew = try ACPCodec.decodeParams(payload, as: ACPSessionNewResult.self)

        let promptID = JSONRPC.ID.string("prompt-1")
        try await transportClient.send(.request(JSONRPC.Request(
            id: promptID,
            method: ACPMethods.sessionPrompt,
            params: try ACPCodec.encodeParams(ACPSessionPromptParams(
                sessionId: sessionNew.sessionId,
                prompt: [.text("cancel by protocol string id")]
            ))
        )))
        try await Task.sleep(nanoseconds: 100_000_000)
        try await transportClient.send(.notification(JSONRPC.Request(
            method: ACPMethods.cancelRequest,
            params: try ACPCodec.encodeParams(ACPCancelRequestParams(requestId: promptID))
        )))

        let promptResponse = try await expectResponse(id: promptID, from: transportClient)
        return promptResponse.error?.code.value ?? JSONRPCErrorCode.internalError
    }

    func runPreCancelRequestPromptScenario(transport: MatrixTransport) async throws -> PreCancelResult {
        let harness: InProcessMatrixHarness
        switch transport {
        case .stdioInProcess:
            harness = try await InProcessMatrixHarness.startStdio(
                modelBehavior: .echo,
                permissionMode: .disabled
            )
        case .wsInProcess:
            harness = try await InProcessMatrixHarness.startWebSocket(
                modelBehavior: .echo,
                permissionMode: .disabled
            )
        }
        defer { Task { await harness.stop() } }

        let transportClient = harness.clientTransport
        try await transportClient.connect()
        defer { Task { await transportClient.close() } }

        try await transportClient.send(.request(JSONRPC.Request(
            id: .int(1),
            method: ACPMethods.initialize,
            params: try ACPCodec.encodeParams(ACPInitializeParams(protocolVersion: 1))
        )))
        _ = try await expectResponse(id: .int(1), from: transportClient)

        try await transportClient.send(.request(JSONRPC.Request(
            id: .int(2),
            method: ACPMethods.sessionNew,
            params: try ACPCodec.encodeParams(ACPSessionNewParams(cwd: FileManager.default.currentDirectoryPath))
        )))
        let sessionNewResponse = try await expectResponse(id: .int(2), from: transportClient)
        guard let payload = sessionNewResponse.result else {
            XCTFail("Expected session/new result")
            return .init(
                intPromptCodeFromStringCancel: JSONRPCErrorCode.internalError,
                stringPromptCodeFromIntCancel: JSONRPCErrorCode.internalError
            )
        }
        let sessionNew = try ACPCodec.decodeParams(payload, as: ACPSessionNewResult.self)

        try await transportClient.send(.notification(JSONRPC.Request(
            method: ACPMethods.cancelRequest,
            params: try ACPCodec.encodeParams(ACPCancelRequestParams(requestId: .string("s2c-3")))
        )))
        try await transportClient.send(.request(JSONRPC.Request(
            id: .int(3),
            method: ACPMethods.sessionPrompt,
            params: try ACPCodec.encodeParams(ACPSessionPromptParams(
                sessionId: sessionNew.sessionId,
                prompt: [.text("pre-cancel string->int")]
            ))
        )))
        let intPromptResponse = try await expectResponse(id: .int(3), from: transportClient)

        try await transportClient.send(.notification(JSONRPC.Request(
            method: ACPMethods.cancelRequest,
            params: try ACPCodec.encodeParams(ACPCancelRequestParams(requestId: .int(4)))
        )))
        try await transportClient.send(.request(JSONRPC.Request(
            id: .string("s2c-4"),
            method: ACPMethods.sessionPrompt,
            params: try ACPCodec.encodeParams(ACPSessionPromptParams(
                sessionId: sessionNew.sessionId,
                prompt: [.text("pre-cancel int->string")]
            ))
        )))
        let stringPromptResponse = try await expectResponse(id: .string("s2c-4"), from: transportClient)

        return .init(
            intPromptCodeFromStringCancel: intPromptResponse.error?.code.value ?? JSONRPCErrorCode.internalError,
            stringPromptCodeFromIntCancel: stringPromptResponse.error?.code.value ?? JSONRPCErrorCode.internalError
        )
    }

    func runForkLoadExportScenario(transport: MatrixTransport) async throws -> ForkLoadExportResult {
        try await withClient(transport: transport, allowPermission: true) { client in
            func step<T>(_ name: String, _ work: () async throws -> T) async throws -> T {
                do {
                    return try await work()
                } catch {
                    throw NSError(domain: "ACPDomainE2EMatrixTests", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "step[\(name)] failed: \(error)"
                    ])
                }
            }

            _ = try await step("initialize") { try await client.initialize(.init(protocolVersion: 1)) }
            let origin = try await step("session_new") {
                try await client.newSession(.init(cwd: FileManager.default.currentDirectoryPath))
            }

            let prompt = try await step("prompt_origin") {
                try await client.prompt(.init(sessionId: origin.sessionId, prompt: [.text("alpha")]))
            }
            let fork = try await step("session_fork") {
                try await client.forkSession(.init(sessionId: origin.sessionId, cwd: FileManager.default.currentDirectoryPath))
            }

            let cwd = FileManager.default.currentDirectoryPath
            try await step("session_load_origin") { try await client.loadSession(.init(sessionId: origin.sessionId, cwd: cwd)) }
            try await step("session_load_fork") { try await client.loadSession(.init(sessionId: fork.sessionId, cwd: cwd)) }

            let originExport = try await step("session_export_origin") {
                try await client.exportSession(.init(sessionId: origin.sessionId))
            }
            let forkExport = try await step("session_export_fork") {
                try await client.exportSession(.init(sessionId: fork.sessionId))
            }

            return .init(
                stopReason: prompt.stopReason,
                forkedSessionDifferent: fork.sessionId != origin.sessionId,
                originExportLooksValid: Self.looksLikeSessionJSONL(originExport.content),
                forkExportLooksValid: Self.looksLikeSessionJSONL(forkExport.content)
            )
        }
    }

    func runForkPromptScenario(transport: MatrixTransport) async throws -> String {
        try await withClient(transport: transport, allowPermission: true) { client in
            actor ChunkBox {
                var value: String?
                func set(_ value: String) { self.value = value }
                func get() -> String? { value }
            }
            let box = ChunkBox()

            _ = try await client.initialize(.init(protocolVersion: 1))
            let origin = try await client.newSession(.init(cwd: FileManager.default.currentDirectoryPath))
            _ = try await client.prompt(.init(sessionId: origin.sessionId, prompt: [.text("alpha")]))
            let fork = try await client.forkSession(.init(sessionId: origin.sessionId, cwd: FileManager.default.currentDirectoryPath))
            await client.setNotificationHandler { notification in
                guard notification.method == ACPMethods.sessionUpdate,
                      let params = try? ACPCodec.decodeParams(notification.params, as: ACPSessionUpdateParams.self),
                      params.sessionId == fork.sessionId else {
                    return
                }
                if params.update.sessionUpdate == .agentMessageChunk, let text = params.update.content?.text {
                    await box.set(text)
                }
            }

            _ = try await client.prompt(.init(sessionId: fork.sessionId, prompt: [.text("beta")]))
            return await box.get() ?? ""
        }
    }

    func runRuntimeFSAndTerminalLifecycleScenario(transport: MatrixTransport) async throws -> RuntimeLifecycleResult {
        let inbox = MatrixResponseInbox()
        let harness: InProcessMatrixHarness
        switch transport {
        case .stdioInProcess:
            harness = try await InProcessMatrixHarness.startStdio(
                permissionMode: .disabled,
                onResponse: { response in await inbox.push(response) }
            )
        case .wsInProcess:
            harness = try await InProcessMatrixHarness.startWebSocket(
                permissionMode: .disabled,
                onResponse: { response in await inbox.push(response) }
            )
        }
        defer { Task { await harness.stop() } }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("acp-matrix-runtime-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("input.txt")
        try "line-1\nline-2\nline-3".write(to: source, atomically: true, encoding: .utf8)
        let target = root.appendingPathComponent("written.txt")

        let client = ACPClientService(
            transport: harness.clientTransport,
            requestTimeoutNanoseconds: 10_000_000_000
        )
        await client.installRuntimes(
            filesystem: ACPLocalFilesystemRuntime(policy: .rooted(root)),
            terminal: ACPProcessTerminalRuntime()
        )

        try await client.connect()
        defer { Task { await client.close() } }

        _ = try await client.initialize(
            .init(
                protocolVersion: 1,
                clientCapabilities: .init(
                    fs: .init(readTextFile: true, writeTextFile: true),
                    terminal: true
                )
            )
        )
        let session = try await client.newSession(.init(cwd: root.path))

        try await harness.serverTransport.send(.request(.init(
            id: .int(101),
            method: ACPMethods.fsReadTextFile,
            params: try ACPCodec.encodeParams(
                ACPReadTextFileParams(sessionId: session.sessionId, path: source.path, line: 2, limit: 1)
            )
        )))
        let fsReadResponse = try await inbox.expect(id: .int(101))
        let fsReadResult = try ACPCodec.decodeResult(fsReadResponse.result, as: ACPReadTextFileResult.self)

        try await harness.serverTransport.send(.request(.init(
            id: .int(102),
            method: ACPMethods.fsWriteTextFile,
            params: try ACPCodec.encodeParams(
                ACPWriteTextFileParams(sessionId: session.sessionId, path: target.path, content: "written-from-matrix")
            )
        )))
        _ = try await inbox.expect(id: .int(102))
        let writtenContent = try String(contentsOf: target, encoding: .utf8)

        try await harness.serverTransport.send(.request(.init(
            id: .int(103),
            method: ACPMethods.terminalCreate,
            params: try ACPCodec.encodeParams(
                ACPTerminalCreateParams(
                    sessionId: session.sessionId,
                    command: "/bin/sh",
                    args: ["-c", "printf 'matrix-terminal'"]
                )
            )
        )))
        let createResponse = try await inbox.expect(id: .int(103))
        let createResult = try ACPCodec.decodeResult(createResponse.result, as: ACPTerminalCreateResult.self)

        try await harness.serverTransport.send(.request(.init(
            id: .int(104),
            method: ACPMethods.terminalWaitForExit,
            params: try ACPCodec.encodeParams(
                ACPTerminalRefParams(sessionId: session.sessionId, terminalId: createResult.terminalId)
            )
        )))
        let waitResponse = try await inbox.expect(id: .int(104))
        let waitResult = try ACPCodec.decodeResult(waitResponse.result, as: ACPTerminalWaitForExitResult.self)

        try await harness.serverTransport.send(.request(.init(
            id: .int(105),
            method: ACPMethods.terminalOutput,
            params: try ACPCodec.encodeParams(
                ACPTerminalRefParams(sessionId: session.sessionId, terminalId: createResult.terminalId)
            )
        )))
        let outputResponse = try await inbox.expect(id: .int(105))
        let outputResult = try ACPCodec.decodeResult(outputResponse.result, as: ACPTerminalOutputResult.self)

        try await harness.serverTransport.send(.request(.init(
            id: .int(106),
            method: ACPMethods.terminalRelease,
            params: try ACPCodec.encodeParams(
                ACPTerminalRefParams(sessionId: session.sessionId, terminalId: createResult.terminalId)
            )
        )))
        _ = try await inbox.expect(id: .int(106))

        try await harness.serverTransport.send(.request(.init(
            id: .int(107),
            method: ACPMethods.terminalOutput,
            params: try ACPCodec.encodeParams(
                ACPTerminalRefParams(sessionId: session.sessionId, terminalId: createResult.terminalId)
            )
        )))
        let afterReleaseOutput = try await inbox.expect(id: .int(107))

        return .init(
            fsReadContent: fsReadResult.content,
            writtenContent: writtenContent,
            terminalOutputContainsToken: outputResult.output.contains("matrix-terminal"),
            terminalExitCode: waitResult.exitCode,
            outputAfterReleaseErrorCode: afterReleaseOutput.error?.code.value ?? JSONRPCErrorCode.internalError
        )
    }

    func runRuntimeTerminalKillScenario(transport: MatrixTransport) async throws -> RuntimeKillResult {
        let inbox = MatrixResponseInbox()
        let harness: InProcessMatrixHarness
        switch transport {
        case .stdioInProcess:
            harness = try await InProcessMatrixHarness.startStdio(
                permissionMode: .disabled,
                onResponse: { response in await inbox.push(response) }
            )
        case .wsInProcess:
            harness = try await InProcessMatrixHarness.startWebSocket(
                permissionMode: .disabled,
                onResponse: { response in await inbox.push(response) }
            )
        }
        defer { Task { await harness.stop() } }

        let client = ACPClientService(
            transport: harness.clientTransport,
            requestTimeoutNanoseconds: 10_000_000_000
        )
        await client.installRuntimes(
            filesystem: ACPLocalFilesystemRuntime(),
            terminal: ACPProcessTerminalRuntime()
        )

        try await client.connect()
        defer { Task { await client.close() } }

        _ = try await client.initialize(
            .init(
                protocolVersion: 1,
                clientCapabilities: .init(terminal: true)
            )
        )
        let session = try await client.newSession(.init(cwd: "/tmp"))

        try await harness.serverTransport.send(.request(.init(
            id: .int(201),
            method: ACPMethods.terminalCreate,
            params: try ACPCodec.encodeParams(
                ACPTerminalCreateParams(
                    sessionId: session.sessionId,
                    command: "/bin/sh",
                    args: ["-c", "echo killed-from-matrix; sleep 5"]
                )
            )
        )))
        let createResponse = try await inbox.expect(id: .int(201))
        let createResult = try ACPCodec.decodeResult(createResponse.result, as: ACPTerminalCreateResult.self)

        try await Task.sleep(nanoseconds: 150_000_000)

        try await harness.serverTransport.send(.request(.init(
            id: .int(202),
            method: ACPMethods.terminalKill,
            params: try ACPCodec.encodeParams(
                ACPTerminalRefParams(sessionId: session.sessionId, terminalId: createResult.terminalId)
            )
        )))
        _ = try await inbox.expect(id: .int(202))

        try await harness.serverTransport.send(.request(.init(
            id: .int(203),
            method: ACPMethods.terminalWaitForExit,
            params: try ACPCodec.encodeParams(
                ACPTerminalRefParams(sessionId: session.sessionId, terminalId: createResult.terminalId)
            )
        )))
        _ = try await inbox.expect(id: .int(203))

        try await harness.serverTransport.send(.request(.init(
            id: .int(204),
            method: ACPMethods.terminalOutput,
            params: try ACPCodec.encodeParams(
                ACPTerminalRefParams(sessionId: session.sessionId, terminalId: createResult.terminalId)
            )
        )))
        let outputResponse = try await inbox.expect(id: .int(204))
        let outputResult = try ACPCodec.decodeResult(outputResponse.result, as: ACPTerminalOutputResult.self)

        try await harness.serverTransport.send(.request(.init(
            id: .int(205),
            method: ACPMethods.terminalRelease,
            params: try ACPCodec.encodeParams(
                ACPTerminalRefParams(sessionId: session.sessionId, terminalId: createResult.terminalId)
            )
        )))
        _ = try await inbox.expect(id: .int(205))

        try await harness.serverTransport.send(.request(.init(
            id: .int(206),
            method: ACPMethods.terminalOutput,
            params: try ACPCodec.encodeParams(
                ACPTerminalRefParams(sessionId: session.sessionId, terminalId: createResult.terminalId)
            )
        )))
        let afterReleaseOutput = try await inbox.expect(id: .int(206))

        return .init(
            outputContainsKilledToken: outputResult.output.contains("killed-from-matrix"),
            outputAfterReleaseErrorCode: afterReleaseOutput.error?.code.value ?? JSONRPCErrorCode.internalError
        )
    }

    static func looksLikeSessionJSONL(_ value: String) -> Bool {
        value.contains("\"type\":\"session\"")
            && value.contains("\"message\"")
    }

    func expectResponse(id: JSONRPC.ID, from transport: any ACPTransport) async throws -> JSONRPC.Response {
        while let message = try await transport.receive() {
            if case .response(let response) = message, response.id! == id {
                return response
            }
        }
        throw ACPTransportError.eof
    }

    func withClient<T>(
        transport: MatrixTransport,
        allowPermission: Bool,
        authMode: MatrixAuthMode = .none,
        modelBehavior: MatrixModelBehavior = .echo,
        permissionMode: MatrixPermissionMode = .bridge,
        operation: @escaping @Sendable (ACPClientService) async throws -> T
    ) async throws -> T {
        switch transport {
        case .stdioInProcess:
            let harness = try await InProcessMatrixHarness.startStdio(
                authMode: authMode,
                modelBehavior: modelBehavior,
                permissionMode: permissionMode
            )
            defer { Task { await harness.stop() } }

            let client = ACPClientService(transport: harness.clientTransport, requestTimeoutNanoseconds: 10_000_000_000)
            await client.setPermissionRequestHandler { _ in
                if allowPermission {
                    return .init(outcome: .selected(.init(optionId: "allow_once")))
                }
                return .init(outcome: .cancelled)
            }

            try await client.connect()
            defer { Task { await client.close() } }
            return try await operation(client)

        case .wsInProcess:
            let harness = try await InProcessMatrixHarness.startWebSocket(
                authMode: authMode,
                modelBehavior: modelBehavior,
                permissionMode: permissionMode
            )
            defer { Task { await harness.stop() } }

            let wsClient = ACPClientService(
                transport: harness.clientTransport,
                requestTimeoutNanoseconds: 10_000_000_000
            )
            await wsClient.setPermissionRequestHandler { _ in
                if allowPermission {
                    return .init(outcome: .selected(.init(optionId: "allow_once")))
                }
                return .init(outcome: .cancelled)
            }

            try await wsClient.connect()
            defer { Task { await wsClient.close() } }
            return try await operation(wsClient)
        }
    }
}

private actor MatrixResponseInbox {
    private var buffered: [JSONRPC.ID: JSONRPC.Response] = [:]
    private var waiters: [JSONRPC.ID: CheckedContinuation<JSONRPC.Response, Error>] = [:]

    func push(_ response: JSONRPC.Response) {
        if let waiter = waiters.removeValue(forKey: response.id!) {
            waiter.resume(returning: response)
            return
        }
        buffered[response.id!] = response
    }

    func expect(id: JSONRPC.ID, timeoutNanoseconds: UInt64 = 2_000_000_000) async throws -> JSONRPC.Response {
        try await withThrowingTaskGroup(of: JSONRPC.Response.self) { group in
            group.addTask { try await self.awaitResponse(id: id) }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                throw NSError(
                    domain: "ACPDomainE2EMatrixTests",
                    code: 1001,
                    userInfo: [NSLocalizedDescriptionKey: "timeout waiting response id=\(id)"]
                )
            }
            let response = try await group.next()!
            group.cancelAll()
            return response
        }
    }

    private func awaitResponse(id: JSONRPC.ID) async throws -> JSONRPC.Response {
        if let response = buffered.removeValue(forKey: id) {
            return response
        }
        return try await withCheckedThrowingContinuation { continuation in
            waiters[id] = continuation
        }
    }
}

private final class InProcessMatrixHarness: @unchecked Sendable {
    let clientTransport: any ACPTransport
    let serverTransport: any ACPTransport
    let permissionBridge: ACPPermissionRequestBridge?
    let onResponse: (@Sendable (JSONRPC.Response) async -> Void)?
    let loop: Task<Void, Never>
    private let closeServer: @Sendable () async -> Void

    init(
        clientTransport: any ACPTransport,
        serverTransport: any ACPTransport,
        closeServer: @escaping @Sendable () async -> Void,
        permissionBridge: ACPPermissionRequestBridge?,
        onResponse: (@Sendable (JSONRPC.Response) async -> Void)?,
        loop: Task<Void, Never>
    ) {
        self.clientTransport = clientTransport
        self.serverTransport = serverTransport
        self.closeServer = closeServer
        self.permissionBridge = permissionBridge
        self.onResponse = onResponse
        self.loop = loop
    }

    static func startWebSocket(
        authMode: ACPDomainE2EMatrixTests.MatrixAuthMode = .none,
        modelBehavior: ACPDomainE2EMatrixTests.MatrixModelBehavior = .echo,
        permissionMode: ACPDomainE2EMatrixTests.MatrixPermissionMode = .bridge,
        onResponse: (@Sendable (JSONRPC.Response) async -> Void)? = nil
    ) async throws -> InProcessMatrixHarness {
        let (serverTransport, port) = try await ACPWebSocketTestHarness.makeServerTransport()
        let clientTransport = WebSocketClientTransport(endpoint: URL(string: "ws://127.0.0.1:\(port)")!)
        return try await start(
            clientTransport: clientTransport,
            serverTransport: serverTransport,
            closeServer: { await serverTransport.close() },
            authMode: authMode,
            modelBehavior: modelBehavior,
            permissionMode: permissionMode,
            onResponse: onResponse
        )
    }

    static func startStdio(
        authMode: ACPDomainE2EMatrixTests.MatrixAuthMode = .none,
        modelBehavior: ACPDomainE2EMatrixTests.MatrixModelBehavior = .echo,
        permissionMode: ACPDomainE2EMatrixTests.MatrixPermissionMode = .bridge,
        onResponse: (@Sendable (JSONRPC.Response) async -> Void)? = nil
    ) async throws -> InProcessMatrixHarness {
        let (clientTransport, serverTransport) = await InMemoryLinkedTransport.makePair()
        try await serverTransport.connect()
        return try await start(
            clientTransport: clientTransport,
            serverTransport: serverTransport,
            closeServer: { await serverTransport.close() },
            authMode: authMode,
            modelBehavior: modelBehavior,
            permissionMode: permissionMode,
            onResponse: onResponse
        )
    }

    private static func start(
        clientTransport: any ACPTransport,
        serverTransport: any ACPTransport,
        closeServer: @escaping @Sendable () async -> Void,
        authMode: ACPDomainE2EMatrixTests.MatrixAuthMode,
        modelBehavior: ACPDomainE2EMatrixTests.MatrixModelBehavior,
        permissionMode: ACPDomainE2EMatrixTests.MatrixPermissionMode,
        onResponse: (@Sendable (JSONRPC.Response) async -> Void)?
    ) async throws -> InProcessMatrixHarness {
        let permissionBridge: ACPPermissionRequestBridge? = {
            guard permissionMode == .bridge else { return nil }
            return ACPPermissionRequestBridge(timeoutNanoseconds: 5_000_000_000)
        }()
        let authMethods: [ACPAuthMethod]
        let authenticationHandler: ACPAgentService.AuthenticationHandler?
        switch authMode {
        case .none:
            authMethods = []
            authenticationHandler = nil
        case .token:
            authMethods = [.init(id: "token", name: "Token")]
            authenticationHandler = { _ in }
        }
        let modelClient: any SKILanguageModelClient = {
            switch modelBehavior {
            case .echo:
                return EchoMatrixClient()
            case .slow:
                return SlowMatrixClient(delayNanoseconds: 1_000_000_000)
            }
        }()
        let permissionRequester: ACPAgentService.PermissionRequester?
        if let permissionBridge {
            permissionRequester = { params in
                try await permissionBridge.requestPermission(params) { request in
                    try await serverTransport.send(.request(request))
                }
            }
        } else {
            permissionRequester = nil
        }

        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: modelClient) },
            agentInfo: .init(name: "matrix-agent", version: "0.1.0"),
            capabilities: .init(
                sessionCapabilities: .init(list: .init(), resume: .init(), fork: .init(), export: .init()),
                loadSession: true
            ),
            authMethods: authMethods,
            authenticationHandler: authenticationHandler,
            permissionRequester: permissionRequester,
            notificationSink: { notification in
                try? await serverTransport.send(.notification(notification))
            }
        )

        let loop = Task<Void, Never> {
            do {
                while let message = try await serverTransport.receive() {
                    switch message {
                    case .request(let request):
                        Task {
                            let response = await service.handle(request)
                            try? await serverTransport.send(.response(response))
                        }
                    case .notification(let notification):
                        await service.handleCancel(notification)
                    case .response(let response):
                        if let permissionBridge {
                            _ = await permissionBridge.handleIncomingResponse(response)
                        }
                        if let onResponse {
                            await onResponse(response)
                        }
                    }
                }
            } catch {
                return
            }
        }

        return InProcessMatrixHarness(
            clientTransport: clientTransport,
            serverTransport: serverTransport,
            closeServer: closeServer,
            permissionBridge: permissionBridge,
            onResponse: onResponse,
            loop: loop
        )
    }

    func stop() async {
        loop.cancel()
        if let permissionBridge {
            await permissionBridge.failAll(ACPTransportError.eof)
        }
        await closeServer()
    }
}

private actor InMemoryLinkedTransport: ACPTransport {
    private var connected = false
    private var peer: InMemoryLinkedTransport?
    private var inbox: [JSONRPCMessage] = []
    private var receivers: [CheckedContinuation<JSONRPCMessage?, Error>] = []

    static func makePair() async -> (client: InMemoryLinkedTransport, server: InMemoryLinkedTransport) {
        let a = InMemoryLinkedTransport()
        let b = InMemoryLinkedTransport()
        await a.setPeer(b)
        await b.setPeer(a)
        return (a, b)
    }

    private func setPeer(_ peer: InMemoryLinkedTransport) {
        self.peer = peer
    }

    func connect() async throws {
        connected = true
    }

    func send(_ message: JSONRPCMessage) async throws {
        guard connected else { throw ACPTransportError.notConnected }
        guard let peer else { throw ACPTransportError.notConnected }
        await peer.enqueue(message)
    }

    private func enqueue(_ message: JSONRPCMessage) {
        if let receiver = receivers.first {
            receivers.removeFirst()
            receiver.resume(returning: message)
            return
        }
        inbox.append(message)
    }

    func receive() async throws -> JSONRPCMessage? {
        guard connected else { throw ACPTransportError.notConnected }
        if !inbox.isEmpty {
            return inbox.removeFirst()
        }
        return try await withCheckedThrowingContinuation { continuation in
            receivers.append(continuation)
        }
    }

    func close() async {
        connected = false
        let continuations = receivers
        receivers.removeAll(keepingCapacity: false)
        for continuation in continuations {
            continuation.resume(returning: nil)
        }
    }
}

private struct EchoMatrixClient: SKILanguageModelClient {
    func respond(_ body: ChatRequestBody) async throws -> sending SKIResponse<ChatResponseBody> {
        let text = body.messages.compactMap { message -> String? in
            if case .user(let content, _) = message, case .text(let value) = content { return value }
            return nil
        }.joined(separator: "\n")
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")

        let payload = """
        {
          "choices": [
            {
              "finish_reason": "stop",
              "message": {
                "content": "matrix: \(escaped)",
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

private struct SlowMatrixClient: SKILanguageModelClient {
    let delayNanoseconds: UInt64

    func respond(_ body: ChatRequestBody) async throws -> sending SKIResponse<ChatResponseBody> {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return try await EchoMatrixClient().respond(body)
    }
}
