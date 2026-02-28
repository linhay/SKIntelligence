import Foundation
@preconcurrency import STJSON

public enum JSONRPCMessage: Sendable, Equatable {
    case request(JSONRPC.Request)
    case notification(JSONRPC.Request)
    case response(JSONRPC.Response)
}

public enum JSONRPCErrorCode {
    public static let parseError = -32700
    public static let invalidRequest = -32600
    public static let methodNotFound = -32601
    public static let invalidParams = -32602
    public static let internalError = -32603
    public static let requestCancelled = -32800
}

public enum JSONRPCCodecError: Error, Sendable, Equatable {
    case invalidEnvelope
    case invalidVersion
}

extension JSONRPC.ID: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .int(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .string(let value):
            hasher.combine(1)
            hasher.combine(value)
        case .null:
            hasher.combine(2)
        }
    }
}

public extension JSONRPC.Request {
    init(id: JSONRPC.ID, method: String, params: AnyCodable? = nil) {
        do {
            try self.init(
                jsonrpc: "2.0",
                method: method,
                params: try Self.makeParams(params),
                id: id
            )
        } catch {
            preconditionFailure("Invalid JSON-RPC request: \(error)")
        }
    }

    init(method: String, params: AnyCodable? = nil) {
        do {
            try self.init(
                jsonrpc: "2.0",
                method: method,
                params: try Self.makeParams(params),
                id: nil
            )
        } catch {
            preconditionFailure("Invalid JSON-RPC notification: \(error)")
        }
    }

    var paramsValue: AnyCodable? {
        guard let params else { return nil }
        switch params {
        case .object(let object):
            return AnyCodable(object)
        case .array(let array):
            return AnyCodable(array)
        }
    }

    private static func makeParams(_ value: AnyCodable?) throws -> JSONRPC.Params? {
        guard let value else { return nil }
        if let object = try? value.decode(to: [String: AnyCodable].self) {
            return .object(object)
        }
        if let array = try? value.decode(to: [AnyCodable].self) {
            return .array(array)
        }
        throw JSONRPCCodecError.invalidEnvelope
    }
}

public extension JSONRPC.Response {
    init(id: JSONRPC.ID, result: AnyCodable? = nil, error: JSONRPC.ErrorObject? = nil) {
        do {
            try self.init(jsonrpc: "2.0", id: id, result: result, error: error)
        } catch {
            preconditionFailure("Invalid JSON-RPC response: \(error)")
        }
    }

    init(id: JSONRPC.ID?, result: AnyCodable? = nil, error: JSONRPC.ErrorObject? = nil) {
        self.init(id: id ?? .null, result: result, error: error)
    }
}

public extension JSONRPC.ErrorObject {
    init(code: Int, message: String, data: AnyCodable? = nil) {
        self.init(code: .init(code), message: message, data: data)
    }
}

public extension Dictionary where Key == JSONRPC.ID {
    subscript(_ optionalKey: JSONRPC.ID?) -> Value? {
        get {
            guard let optionalKey else { return nil }
            return self[optionalKey]
        }
        set {
            guard let optionalKey else { return }
            self[optionalKey] = newValue
        }
    }
}

public func == (lhs: JSONRPC.ErrorCode, rhs: Int) -> Bool {
    lhs.value == rhs
}

public func == (lhs: Int, rhs: JSONRPC.ErrorCode) -> Bool {
    rhs == lhs
}

public func == (lhs: JSONRPC.ErrorCode?, rhs: Int) -> Bool {
    lhs?.value == rhs
}

public func == (lhs: Int, rhs: JSONRPC.ErrorCode?) -> Bool {
    rhs == lhs
}

public enum JSONRPCCodec {
    public static func encode(_ message: JSONRPCMessage) throws -> Data {
        switch message {
        case .request(let request), .notification(let request):
            return try makeEncoder().encode(request)
        case .response(let response):
            return try JSONRPC.encodeResponse(response, encoder: makeEncoder())
        }
    }

    public static func decode(_ data: Data) throws -> JSONRPCMessage {
        try validateVersionIfPresent(data)

        if let inbound = try? JSONRPC.decodeInbound(from: data) {
            switch inbound {
            case .single(let request):
                return request.id == nil ? .notification(request) : .request(request)
            case .batch:
                throw JSONRPCCodecError.invalidEnvelope
            }
        }

        if let response = try? JSONDecoder().decode(JSONRPC.Response.self, from: data) {
            return .response(response)
        }

        throw JSONRPCCodecError.invalidEnvelope
    }

    public static func toValue<T: Encodable>(_ value: T) throws -> AnyCodable {
        let data = try makeEncoder().encode(value)
        return try JSONDecoder().decode(AnyCodable.self, from: data)
    }

    public static func fromValue<T: Decodable>(_ value: AnyCodable, as type: T.Type = T.self) throws -> T {
        let data = try makeEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return encoder
    }
}

private extension JSONRPCCodec {
    static func validateVersionIfPresent(_ data: Data) throws {
        guard
            let raw = try? JSONSerialization.jsonObject(with: data),
            let object = raw as? [String: Any],
            let version = object["jsonrpc"] as? String
        else {
            return
        }
        guard version == "2.0" else {
            throw JSONRPCCodecError.invalidVersion
        }
    }
}

public struct JSONRPCLineFramer: Sendable {
    public init() {}

    public func encodeLine(_ message: JSONRPCMessage) throws -> Data {
        var data = try JSONRPCCodec.encode(message)
        data.append(0x0A)
        return data
    }

    public func decodeLine(_ line: String) throws -> JSONRPCMessage {
        guard let data = line.data(using: .utf8) else {
            throw JSONRPCCodecError.invalidEnvelope
        }
        return try JSONRPCCodec.decode(data)
    }
}
