import Foundation
import SKIJSONRPC

#if os(iOS) || os(tvOS) || os(watchOS)
public final class ProcessStdioTransport: ACPTransport, @unchecked Sendable {
    public init(executable: String, arguments: [String] = []) {
        _ = executable
        _ = arguments
    }

    public func connect() async throws {
        throw ACPTransportError.unsupported("Process stdio transport is unavailable on this platform")
    }

    public func send(_ message: JSONRPCMessage) async throws {
        _ = message
        throw ACPTransportError.notConnected
    }

    public func receive() async throws -> JSONRPCMessage? {
        throw ACPTransportError.notConnected
    }

    public func close() async {}
}
#else
public final class ProcessStdioTransport: ACPTransport, @unchecked Sendable {
    private let executable: String
    private let arguments: [String]
    private let framer = JSONRPCLineFramer()
    private let stateQueue = DispatchQueue(label: "SKIACPTransport.ProcessStdioTransport.state")
    private let readQueue = DispatchQueue(label: "SKIACPTransport.ProcessStdioTransport.read")
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?

    public init(executable: String, arguments: [String] = []) {
        self.executable = executable
        self.arguments = arguments
    }

    public func connect() async throws {
        let alreadyConnected = stateQueue.sync { process != nil }
        if alreadyConnected {
            return
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments

        let input = Pipe()
        let output = Pipe()
        p.standardInput = input
        p.standardOutput = output
        p.standardError = FileHandle.standardError

        try p.run()

        stateQueue.sync {
            process = p
            stdinHandle = input.fileHandleForWriting
            stdoutHandle = output.fileHandleForReading
        }
    }

    public func send(_ message: JSONRPCMessage) async throws {
        let stdinHandle = stateQueue.sync { self.stdinHandle }
        guard let stdinHandle else { throw ACPTransportError.notConnected }
        let data = try framer.encodeLine(message)
        try stdinHandle.write(contentsOf: data)
    }

    public func receive() async throws -> JSONRPCMessage? {
        let stdoutHandle = stateQueue.sync { self.stdoutHandle }
        guard let stdoutHandle else { throw ACPTransportError.notConnected }
        guard let line = try Self.readLine(from: stdoutHandle, queue: readQueue) else {
            return nil
        }
        return try framer.decodeLine(line)
    }

    public func close() async {
        let snapshot = stateQueue.sync { () -> (Process?, FileHandle?, FileHandle?) in
            let p = self.process
            let inHandle = self.stdinHandle
            let outHandle = self.stdoutHandle
            self.process = nil
            self.stdinHandle = nil
            self.stdoutHandle = nil
            return (p, inHandle, outHandle)
        }
        let process = snapshot.0
        let stdinHandle = snapshot.1
        let stdoutHandle = snapshot.2

        if let process {
            if process.isRunning {
                process.terminate()
            }
        }
        try? stdinHandle?.close()
        try? stdoutHandle?.close()
    }

    private static func readLine(from handle: FileHandle, queue: DispatchQueue) throws -> String? {
        try queue.sync {
            var data = Data()
            while true {
                guard let chunk = try handle.read(upToCount: 1), !chunk.isEmpty else {
                    if data.isEmpty { return nil }
                    break
                }
                if chunk[0] == 0x0A { break }
                data.append(chunk)
            }
            return String(data: data, encoding: .utf8)
        }
    }
}
#endif
