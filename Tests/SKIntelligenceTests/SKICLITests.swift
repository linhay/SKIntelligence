import XCTest
@testable import SKICLIShared
@testable import SKIACPClient
@testable import SKIACPTransport

final class SKICLITests: XCTestCase {
    func testACPClientConnectRequiresCmdForStdio() throws {
        do {
            _ = try ACPCLITransportFactory.makeClientTransport(
                kind: .stdio,
                cmd: nil,
                args: [],
                endpoint: nil,
                wsHeartbeatMS: 15_000,
                wsReconnectAttempts: 2,
                wsReconnectBaseDelayMS: 200,
                maxInFlightSends: 64
            )
            XCTFail("Expected invalid input error")
        } catch let error as SKICLIValidationError {
            guard case .invalidInput(let message) = error else {
                return XCTFail("Unexpected CLIError: \(error)")
            }
            XCTAssertEqual(message, "--cmd is required for stdio transport")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testACPClientConnectRequiresEndpointForWS() throws {
        do {
            _ = try ACPCLITransportFactory.makeClientTransport(
                kind: .ws,
                cmd: nil,
                args: [],
                endpoint: nil,
                wsHeartbeatMS: 15_000,
                wsReconnectAttempts: 2,
                wsReconnectBaseDelayMS: 200,
                maxInFlightSends: 64
            )
            XCTFail("Expected invalid input error")
        } catch let error as SKICLIValidationError {
            guard case .invalidInput(let message) = error else {
                return XCTFail("Unexpected CLIError: \(error)")
            }
            XCTAssertEqual(message, "--endpoint is required for ws transport")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testACPClientConnectBuildsWSTransportWithValidEndpoint() throws {
        let transport = try ACPCLITransportFactory.makeClientTransport(
            kind: .ws,
            cmd: nil,
            args: [],
            endpoint: "ws://127.0.0.1:8900",
            wsHeartbeatMS: 0,
            wsReconnectAttempts: -3,
            wsReconnectBaseDelayMS: 0,
            maxInFlightSends: 1
        )
        XCTAssertTrue(transport is WebSocketClientTransport)
    }

    func testACPServeBuildsWebSocketServerTransportWithValidListen() throws {
        let transport = try ACPCLITransportFactory.makeServerTransport(
            kind: .ws,
            listen: "127.0.0.1:8900",
            maxInFlightSends: 8
        )
        XCTAssertTrue(transport is WebSocketServerTransport)
    }

    func testACPServeRejectsInvalidListenAddress() throws {
        do {
            _ = try ACPCLITransportFactory.makeServerTransport(
                kind: .ws,
                listen: "invalid-listen",
                maxInFlightSends: 8
            )
            XCTFail("Expected invalid input")
        } catch let error as SKICLIValidationError {
            guard case .invalidInput(let message) = error else {
                return XCTFail("Unexpected validation error: \(error)")
            }
            XCTAssertEqual(message, "--listen must be in host:port format with port in 1...65535")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMillisecondsToNanosecondsNonNegative() {
        XCTAssertEqual(ACPCLITransportFactory.millisecondsToNanosecondsNonNegative(nil), nil)
        XCTAssertEqual(ACPCLITransportFactory.millisecondsToNanosecondsNonNegative(0), 0)
        XCTAssertEqual(ACPCLITransportFactory.millisecondsToNanosecondsNonNegative(12), 12_000_000)
        XCTAssertEqual(ACPCLITransportFactory.millisecondsToNanosecondsNonNegative(-8), 0)
    }

    func testExitCodeMapperForValidationError() {
        let code = SKICLIExitCodeMapper.exitCode(for: SKICLIValidationError.invalidInput("bad input"))
        XCTAssertEqual(code, .invalidInput)
        XCTAssertEqual(code.rawValue, 2)
    }

    func testExitCodeMapperForUnknownErrorFallsBackToInternal() {
        struct DummyError: Error {}
        let code = SKICLIExitCodeMapper.exitCode(for: DummyError())
        XCTAssertEqual(code, .internalError)
        XCTAssertEqual(code.rawValue, 5)
    }

    func testExitCodeMapperForTransportErrorUsesUpstreamFailure() {
        let code = SKICLIExitCodeMapper.exitCode(for: ACPTransportError.notConnected)
        XCTAssertEqual(code, .upstreamFailure)
        XCTAssertEqual(code.rawValue, 4)
    }

    func testExitCodeMapperForClientServiceErrorUsesUpstreamFailure() {
        let code = SKICLIExitCodeMapper.exitCode(for: ACPClientServiceError.requestTimeout(method: "session/new"))
        XCTAssertEqual(code, .upstreamFailure)
        XCTAssertEqual(code.rawValue, 4)
    }

    func testExitCodeMapperForURLErrorUsesUpstreamFailure() {
        let code = SKICLIExitCodeMapper.exitCode(for: URLError(.timedOut))
        XCTAssertEqual(code, .upstreamFailure)
        XCTAssertEqual(code.rawValue, 4)
    }

    func testSessionUpdateJSONPayloadShape() throws {
        let json = try ACPCLIOutputFormatter.sessionUpdateJSON(
            sessionId: "sess_1",
            update: "agent_message_chunk",
            text: "hello"
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: String]
        )
        XCTAssertEqual(object["type"], "session_update")
        XCTAssertEqual(object["sessionId"], "sess_1")
        XCTAssertEqual(object["update"], "agent_message_chunk")
        XCTAssertEqual(object["text"], "hello")
    }

    func testPromptResultJSONPayloadShape() throws {
        let json = try ACPCLIOutputFormatter.promptResultJSON(
            sessionId: "sess_2",
            stopReason: "end_turn"
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: String]
        )
        XCTAssertEqual(object["sessionId"], "sess_2")
        XCTAssertEqual(object["stopReason"], "end_turn")
    }

    func testServePermissionModeSemantics() {
        XCTAssertFalse(SKICLIServePermissionMode.disabled.enabled)
        XCTAssertFalse(SKICLIServePermissionMode.disabled.allowOnBridgeError)
        XCTAssertEqual(SKICLIServePermissionMode.disabled.policyMode, .allow)

        XCTAssertTrue(SKICLIServePermissionMode.permissive.enabled)
        XCTAssertTrue(SKICLIServePermissionMode.permissive.allowOnBridgeError)
        XCTAssertEqual(SKICLIServePermissionMode.permissive.policyMode, .ask)

        XCTAssertTrue(SKICLIServePermissionMode.required.enabled)
        XCTAssertFalse(SKICLIServePermissionMode.required.allowOnBridgeError)
        XCTAssertEqual(SKICLIServePermissionMode.required.policyMode, .ask)
    }

    func testClientPermissionDecisionSemantics() {
        XCTAssertTrue(SKICLIClientPermissionDecision.allow.allowValue)
        XCTAssertFalse(SKICLIClientPermissionDecision.deny.allowValue)
    }
}
