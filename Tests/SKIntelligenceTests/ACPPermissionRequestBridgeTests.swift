import XCTest
@testable import SKIACP
@testable import SKIACPAgent
@testable import SKIJSONRPC

final class ACPPermissionRequestBridgeTests: XCTestCase {
    func testPermissionRequestRoundTripSuccess() async throws {
        let bridge = ACPPermissionRequestBridge(timeoutNanoseconds: 500_000_000)
        let sent = SentRequestBox()

        async let result: ACPSessionPermissionRequestResult = bridge.requestPermission(
            .init(
                sessionId: "sess_1",
                toolCall: .init(toolCallId: "call_1", title: "Read file"),
                options: [
                    .init(optionId: "allow_once", name: "Allow once", kind: .allowOnce)
                ]
            )
        ) { request in
            await sent.set(request)
        }

        let request = await sent.wait()
        XCTAssertEqual(request.method, ACPMethods.sessionRequestPermission)

        let handled = await bridge.handleIncomingResponse(.init(
            id: request.id,
            result: try ACPCodec.encodeParams(
                ACPSessionPermissionRequestResult(
                    outcome: .selected(.init(optionId: "allow_once"))
                )
            )
        ))
        XCTAssertTrue(handled)

        let value = try await result
        guard case .selected(let selected) = value.outcome else {
            return XCTFail("Expected selected outcome")
        }
        XCTAssertEqual(selected.optionId, "allow_once")
    }

    func testPermissionRequestRPCErrorPropagates() async throws {
        let bridge = ACPPermissionRequestBridge(timeoutNanoseconds: 500_000_000)
        let sent = SentRequestBox()

        let task = Task {
            try await bridge.requestPermission(
                .init(
                    sessionId: "sess_2",
                    toolCall: .init(toolCallId: "call_2", title: "Write file"),
                    options: [
                        .init(optionId: "reject_once", name: "Reject once", kind: .rejectOnce)
                    ]
                )
            ) { request in
                await sent.set(request)
            }
        }

        let request = await sent.wait()
        _ = await bridge.handleIncomingResponse(.init(
            id: request.id,
            error: .init(code: JSONRPCErrorCode.methodNotFound, message: "unsupported")
        ))

        do {
            _ = try await task.value
            XCTFail("Expected rpcError")
        } catch let error as ACPPermissionRequestBridgeError {
            guard case .rpcError(let code, let message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(code, JSONRPCErrorCode.methodNotFound)
            XCTAssertEqual(message, "unsupported")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPermissionRequestTimeout() async throws {
        let bridge = ACPPermissionRequestBridge(timeoutNanoseconds: 40_000_000)
        do {
            _ = try await bridge.requestPermission(
                .init(
                    sessionId: "sess_3",
                    toolCall: .init(toolCallId: "call_3", title: "Exec command"),
                    options: [
                        .init(optionId: "allow_once", name: "Allow once", kind: .allowOnce)
                    ]
                )
            ) { _ in
                // no response
            }
            XCTFail("Expected timeout")
        } catch let error as ACPPermissionRequestBridgeError {
            XCTAssertEqual(error, .requestTimeout)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private actor SentRequestBox {
    private var request: JSONRPCRequest?

    func set(_ value: JSONRPCRequest) {
        request = value
    }

    func wait() async -> JSONRPCRequest {
        while request == nil {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return request!
    }
}
