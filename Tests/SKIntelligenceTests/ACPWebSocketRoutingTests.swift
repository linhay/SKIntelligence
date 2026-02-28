import XCTest
import STJSON
@testable import SKIACP
@testable import SKIACPTransport

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

        let promptRequest = JSONRPC.Request(
            id: .int(3),
            method: "session/prompt",
            params: AnyCodable(["sessionId": AnyCodable("sess_1")])
        )
        try await clientTransport.send(.request(promptRequest))

        guard case .request(let routedPrompt)? = try await serverTransport.receive() else {
            return XCTFail("Expected routed request")
        }
        guard case .string(let internalIDText)? = routedPrompt.id else {
            return XCTFail("Expected internal request id to be string")
        }
        XCTAssertTrue(internalIDText.hasPrefix("s2c-"))

        let cancelNotification = JSONRPC.Request(
            method: "$/cancel_request",
            params: AnyCodable(["requestId": AnyCodable(Double(3))])
        )
        try await clientTransport.send(.notification(cancelNotification))

        guard case .notification(let routedCancel)? = try await serverTransport.receive() else {
            return XCTFail("Expected routed notification")
        }
        guard case .object(let routedParams)? = routedCancel.params else {
            return XCTFail("Expected cancel_request params object")
        }
        guard let routedRequestID = routedParams["requestId"]?.value as? String else {
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

        let cancelNotification = JSONRPC.Request(
            method: "$/cancel_request",
            params: AnyCodable(["requestId": AnyCodable(Double(42))])
        )
        try await clientTransport.send(.notification(cancelNotification))

        guard case .notification(let routedCancel)? = try await serverTransport.receive() else {
            return XCTFail("Expected routed notification")
        }
        guard case .object(let routedParams)? = routedCancel.params else {
            return XCTFail("Expected cancel_request params object")
        }
        guard let routedRequestID = numericDouble(from: routedParams["requestId"]?.value) else {
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

        let promptRequest = JSONRPC.Request(
            id: .string("prompt-a"),
            method: "session/prompt",
            params: AnyCodable(["sessionId": AnyCodable("sess_1")])
        )
        try await clientTransport.send(.request(promptRequest))

        guard case .request(let routedPrompt)? = try await serverTransport.receive() else {
            return XCTFail("Expected routed request")
        }
        guard case .string(let internalIDText)? = routedPrompt.id else {
            return XCTFail("Expected internal request id to be string")
        }
        XCTAssertTrue(internalIDText.hasPrefix("s2c-"))

        let cancelNotification = JSONRPC.Request(
            method: "$/cancel_request",
            params: AnyCodable(["requestId": AnyCodable("prompt-a")])
        )
        try await clientTransport.send(.notification(cancelNotification))

        guard case .notification(let routedCancel)? = try await serverTransport.receive() else {
            return XCTFail("Expected routed notification")
        }
        guard case .object(let routedParams)? = routedCancel.params else {
            return XCTFail("Expected cancel_request params object")
        }
        guard let routedRequestID = routedParams["requestId"]?.value as? String else {
            return XCTFail("Expected remapped requestId string")
        }
        XCTAssertEqual(routedRequestID, internalIDText)
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
}
