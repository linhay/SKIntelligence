import Foundation

public enum JSONRPCVersion: String, Codable, Sendable {
    case v2 = "2.0"
}

public enum JSONRPCID: Codable, Hashable, Sendable, Equatable {
    case int(Int)
    case string(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "JSONRPC id must be int or string")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        }
    }
}

public struct JSONRPCErrorObject: Codable, Sendable, Equatable {
    public let code: Int
    public let message: String
    public let data: JSONValue?

    public init(code: Int, message: String, data: JSONValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }
}

public struct JSONRPCRequest: Codable, Sendable, Equatable {
    public let jsonrpc: JSONRPCVersion
    public let id: JSONRPCID
    public let method: String
    public let params: JSONValue?

    public init(id: JSONRPCID, method: String, params: JSONValue? = nil) {
        self.jsonrpc = .v2
        self.id = id
        self.method = method
        self.params = params
    }
}

public struct JSONRPCNotification: Codable, Sendable, Equatable {
    public let jsonrpc: JSONRPCVersion
    public let method: String
    public let params: JSONValue?

    public init(method: String, params: JSONValue? = nil) {
        self.jsonrpc = .v2
        self.method = method
        self.params = params
    }
}

public struct JSONRPCResponse: Codable, Sendable, Equatable {
    public let jsonrpc: JSONRPCVersion
    public let id: JSONRPCID
    public let result: JSONValue?
    public let error: JSONRPCErrorObject?

    public init(id: JSONRPCID, result: JSONValue? = nil, error: JSONRPCErrorObject? = nil) {
        self.jsonrpc = .v2
        self.id = id
        self.result = result
        self.error = error
    }
}

public enum JSONRPCMessage: Sendable, Equatable {
    case request(JSONRPCRequest)
    case notification(JSONRPCNotification)
    case response(JSONRPCResponse)
}

public enum JSONRPCErrorCode {
    public static let parseError = -32700
    public static let invalidRequest = -32600
    public static let methodNotFound = -32601
    public static let invalidParams = -32602
    public static let internalError = -32603
    public static let requestCancelled = -32800
}
