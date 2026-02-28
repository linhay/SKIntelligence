import Foundation
import SKIACP

public enum ACPTransportError: Error, LocalizedError, Sendable {
    case notConnected
    case unsupported(String)
    case eof

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Transport is not connected"
        case .unsupported(let message):
            return message
        case .eof:
            return "Transport reached EOF"
        }
    }
}

public protocol ACPTransport: Sendable {
    func connect() async throws
    func send(_ message: JSONRPCMessage) async throws
    func receive() async throws -> JSONRPCMessage?
    func close() async
}
