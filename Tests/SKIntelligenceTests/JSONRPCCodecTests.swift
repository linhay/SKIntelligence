import XCTest
 import STJSON
 import SKIACP

final class JSONRPCCodecTests: XCTestCase {

    func testEncodeDecodeRequest() throws {
        let req = JSONRPC.Request(id: .int(1), method: "initialize", params: AnyCodable(["protocolVersion": AnyCodable(1)]))
        let data = try JSONRPCCodec.encode(.request(req))
        let decoded = try JSONRPCCodec.decode(data)
        XCTAssertEqual(decoded, .request(req))
    }

    func testEncodeDecodeNotification() throws {
        let n = JSONRPC.Request(method: "session/update", params: AnyCodable(["sessionId": AnyCodable("s1")]))
        let data = try JSONRPCCodec.encode(.notification(n))
        let decoded = try JSONRPCCodec.decode(data)
        XCTAssertEqual(decoded, .notification(n))
    }

    func testEncodeDecodeResponseError() throws {
        let r = JSONRPC.Response(id: .string("abc"), error: JSONRPC.ErrorObject(code: -32601, message: "not found"))
        let data = try JSONRPCCodec.encode(.response(r))
        let decoded = try JSONRPCCodec.decode(data)
        XCTAssertEqual(decoded, .response(r))
    }

    func testLineFramerRoundTrip() throws {
        let req = JSONRPC.Request(id: .int(2), method: "ping", params: nil)
        let framer = JSONRPCLineFramer()
        let data = try framer.encodeLine(.request(req))
        let line = String(decoding: data, as: UTF8.self)
        let decoded = try framer.decodeLine(line)
        XCTAssertEqual(decoded, .request(req))
    }

    func testDecodeInvalidEnvelopeArray() throws {
        let raw = Data("[1,2,3]".utf8)
        XCTAssertThrowsError(try JSONRPCCodec.decode(raw)) { error in
            XCTAssertEqual(error as? JSONRPCCodecError, .invalidEnvelope)
        }
    }

    func testDecodeInvalidIDType() throws {
        let raw = Data(#"{"jsonrpc":"2.0","id":{"x":1},"result":{"ok":true}}"#.utf8)
        XCTAssertThrowsError(try JSONRPCCodec.decode(raw)) { error in
            XCTAssertEqual(error as? JSONRPCCodecError, .invalidEnvelope)
        }
    }

    func testLineFramerTrimsWhitespace() throws {
        let framer = JSONRPCLineFramer()
        let line = "  {\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"ping\"} \n"
        let decoded = try framer.decodeLine(line)
        XCTAssertEqual(decoded, .request(.init(id: .int(3), method: "ping", params: nil)))
    }

    func testDecodeInvalidVersion() throws {
        let raw = Data(#"{"jsonrpc":"1.0","id":1,"method":"ping"}"#.utf8)
        XCTAssertThrowsError(try JSONRPCCodec.decode(raw)) { error in
            XCTAssertEqual(error as? JSONRPCCodecError, .invalidVersion)
        }
    }

    func testDecodeResponseWithBothResultAndErrorIsInvalid() throws {
        let raw = Data(#"{"jsonrpc":"2.0","id":1,"result":{"ok":true},"error":{"code":-32603,"message":"x"}}"#.utf8)
        XCTAssertThrowsError(try JSONRPCCodec.decode(raw)) { error in
            XCTAssertEqual(error as? JSONRPCCodecError, .invalidEnvelope)
        }
    }

    func testDecodeResponseWithNeitherResultNorErrorIsInvalid() throws {
        let raw = Data(#"{"jsonrpc":"2.0","id":1}"#.utf8)
        XCTAssertThrowsError(try JSONRPCCodec.decode(raw)) { error in
            XCTAssertEqual(error as? JSONRPCCodecError, .invalidEnvelope)
        }
    }

    func testLineFramerRejectsEmptyLine() throws {
        let framer = JSONRPCLineFramer()
        XCTAssertThrowsError(try framer.decodeLine("   \n")) { error in
            XCTAssertEqual(error as? JSONRPCCodecError, .invalidEnvelope)
        }
    }

    func testLineFramerLargePayloadRoundTrip() throws {
        let large = String(repeating: "x", count: 512 * 1024)
        let req = JSONRPC.Request(
            id: .int(42),
            method: "session/prompt",
            params: AnyCodable(["text": AnyCodable(large)])
        )
        let framer = JSONRPCLineFramer()
        let data = try framer.encodeLine(.request(req))
        let line = String(decoding: data, as: UTF8.self)
        let decoded = try framer.decodeLine(line)
        XCTAssertEqual(decoded, .request(req))
    }

    func testEncodeRequestDoesNotEscapeForwardSlashesInMethod() throws {
        let req = JSONRPC.Request(id: .int(7), method: "session/new", params: nil)
        let data = try JSONRPCCodec.encode(.request(req))
        let raw = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(raw.contains("\"method\":\"session/new\""))
        XCTAssertFalse(raw.contains("session\\/new"))
    }
}
