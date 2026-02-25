import XCTest
@testable import SKIACPTransport
@testable import SKIJSONRPC

final class ACPWebSocketRoutingTests: XCTestCase {
    func testCancelRequestNotificationRequestIDIsRemappedToInternalID() async throws {
        let (serverTransport, port) = try await ACPWebSocketTestHarness.makeServerTransport()
        let clientTransport = WebSocketClientTransport(endpoint: URL(string: "ws://127.0.0.1:\(port)")!)

        try await clientTransport.connect()
        defer {
            Task {
                await clientTransport.close()
                await serverTransport.close()
            }
        }

        let promptRequest = JSONRPCRequest(
            id: .int(3),
            method: "session/prompt",
            params: .object(["sessionId": .string("sess_1")])
        )
        try await clientTransport.send(.request(promptRequest))

        guard case .request(let routedPrompt)? = try await serverTransport.receive() else {
            return XCTFail("Expected routed request")
        }
        guard case .string(let internalIDText) = routedPrompt.id else {
            return XCTFail("Expected internal request id to be string")
        }
        XCTAssertTrue(internalIDText.hasPrefix("s2c-"))

        let cancelNotification = JSONRPCNotification(
            method: "$/cancel_request",
            params: .object(["requestId": .number(3)])
        )
        try await clientTransport.send(.notification(cancelNotification))

        guard case .notification(let routedCancel)? = try await serverTransport.receive() else {
            return XCTFail("Expected routed notification")
        }
        guard case .object(let routedParams)? = routedCancel.params else {
            return XCTFail("Expected cancel_request params object")
        }
        guard case .string(let routedRequestID)? = routedParams["requestId"] else {
            return XCTFail("Expected remapped requestId string")
        }
        XCTAssertEqual(routedRequestID, internalIDText)
    }

    func testCancelRequestNotificationKeepsOriginalIDWhenNoMappingFound() async throws {
        let (serverTransport, port) = try await ACPWebSocketTestHarness.makeServerTransport()
        let clientTransport = WebSocketClientTransport(endpoint: URL(string: "ws://127.0.0.1:\(port)")!)

        try await clientTransport.connect()
        defer {
            Task {
                await clientTransport.close()
                await serverTransport.close()
            }
        }

        let cancelNotification = JSONRPCNotification(
            method: "$/cancel_request",
            params: .object(["requestId": .number(42)])
        )
        try await clientTransport.send(.notification(cancelNotification))

        guard case .notification(let routedCancel)? = try await serverTransport.receive() else {
            return XCTFail("Expected routed notification")
        }
        guard case .object(let routedParams)? = routedCancel.params else {
            return XCTFail("Expected cancel_request params object")
        }
        guard case .number(let routedRequestID)? = routedParams["requestId"] else {
            return XCTFail("Expected original numeric requestId")
        }
        XCTAssertEqual(routedRequestID, 42)
    }

    func testCancelRequestNotificationStringRequestIDIsRemappedToInternalID() async throws {
        let (serverTransport, port) = try await ACPWebSocketTestHarness.makeServerTransport()
        let clientTransport = WebSocketClientTransport(endpoint: URL(string: "ws://127.0.0.1:\(port)")!)

        try await clientTransport.connect()
        defer {
            Task {
                await clientTransport.close()
                await serverTransport.close()
            }
        }

        let promptRequest = JSONRPCRequest(
            id: .string("prompt-a"),
            method: "session/prompt",
            params: .object(["sessionId": .string("sess_1")])
        )
        try await clientTransport.send(.request(promptRequest))

        guard case .request(let routedPrompt)? = try await serverTransport.receive() else {
            return XCTFail("Expected routed request")
        }
        guard case .string(let internalIDText) = routedPrompt.id else {
            return XCTFail("Expected internal request id to be string")
        }
        XCTAssertTrue(internalIDText.hasPrefix("s2c-"))

        let cancelNotification = JSONRPCNotification(
            method: "$/cancel_request",
            params: .object(["requestId": .string("prompt-a")])
        )
        try await clientTransport.send(.notification(cancelNotification))

        guard case .notification(let routedCancel)? = try await serverTransport.receive() else {
            return XCTFail("Expected routed notification")
        }
        guard case .object(let routedParams)? = routedCancel.params else {
            return XCTFail("Expected cancel_request params object")
        }
        guard case .string(let routedRequestID)? = routedParams["requestId"] else {
            return XCTFail("Expected remapped requestId string")
        }
        XCTAssertEqual(routedRequestID, internalIDText)
    }
}
