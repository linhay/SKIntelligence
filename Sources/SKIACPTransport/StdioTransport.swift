import Foundation
import SKIACP

public actor StdioTransport: ACPTransport {
    private let framer = JSONRPCLineFramer()
    private var connected = false

    public init() {}

    public func connect() async throws {
        connected = true
    }

    public func send(_ message: JSONRPCMessage) async throws {
        guard connected else { throw ACPTransportError.notConnected }
        let data = try framer.encodeLine(message)
        FileHandle.standardOutput.write(data)
    }

    public func receive() async throws -> JSONRPCMessage? {
        guard connected else { throw ACPTransportError.notConnected }
        guard let line = readLine(strippingNewline: true) else {
            return nil
        }
        if line.isEmpty {
            return try await receive()
        }
        return try framer.decodeLine(line)
    }

    public func close() async {
        connected = false
    }
}
