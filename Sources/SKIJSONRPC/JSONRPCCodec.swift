import Foundation

public enum JSONRPCCodecError: Error, Sendable, Equatable {
    case invalidEnvelope
    case invalidVersion
}

public enum JSONRPCCodec {
    public static func encode(_ message: JSONRPCMessage) throws -> Data {
        let encoder = JSONEncoder()
        switch message {
        case .request(let request):
            return try encoder.encode(request)
        case .notification(let notification):
            return try encoder.encode(notification)
        case .response(let response):
            return try encoder.encode(response)
        }
    }

    public static func decode(_ data: Data) throws -> JSONRPCMessage {
        try validateVersionIfPresent(data)
        let decoder = JSONDecoder()
        if let request = try? decoder.decode(JSONRPCRequest.self, from: data) {
            guard request.jsonrpc == .v2 else { throw JSONRPCCodecError.invalidVersion }
            return .request(request)
        }
        if let response = try? decoder.decode(JSONRPCResponse.self, from: data) {
            guard response.jsonrpc == .v2 else { throw JSONRPCCodecError.invalidVersion }
            let hasResult = response.result != nil
            let hasError = response.error != nil
            guard hasResult != hasError else {
                throw JSONRPCCodecError.invalidEnvelope
            }
            return .response(response)
        }
        if let notification = try? decoder.decode(JSONRPCNotification.self, from: data) {
            guard notification.jsonrpc == .v2 else { throw JSONRPCCodecError.invalidVersion }
            return .notification(notification)
        }
        throw JSONRPCCodecError.invalidEnvelope
    }

    public static func toValue<T: Encodable>(_ value: T) throws -> JSONValue {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    public static func fromValue<T: Decodable>(_ value: JSONValue, as type: T.Type = T.self) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
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
        guard version == JSONRPCVersion.v2.rawValue else {
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
        let clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = clean.data(using: .utf8) else {
            throw JSONRPCCodecError.invalidEnvelope
        }
        return try JSONRPCCodec.decode(data)
    }
}
