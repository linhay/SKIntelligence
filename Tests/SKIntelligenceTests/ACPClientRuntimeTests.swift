import XCTest
 import STJSON
@testable import SKIACP
@testable import SKIACPClient
@testable import SKIACPTransport

final class ACPClientRuntimeTests: XCTestCase {
    func testLocalFilesystemRuntimeReadWriteAndRootPolicy() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("acp-runtime-root-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let runtime = ACPLocalFilesystemRuntime(policy: .rooted(root))
        let inRootFile = root.appendingPathComponent("notes.txt").path

        _ = try await runtime.writeTextFile(
            .init(sessionId: "sess_1", path: inRootFile, content: "a\nb\nc")
        )

        let read = try await runtime.readTextFile(
            .init(sessionId: "sess_1", path: inRootFile, line: 2, limit: 2)
        )
        XCTAssertEqual(read.content, "b\nc")

        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("outside-\(UUID().uuidString).txt").path
        defer { try? FileManager.default.removeItem(atPath: outside) }

        do {
            _ = try await runtime.readTextFile(.init(sessionId: "sess_1", path: outside))
            XCTFail("Expected permission denied")
        } catch let error as ACPRuntimeError {
            guard case .permissionDenied = error else {
                return XCTFail("Expected permission denied, got \(error)")
            }
        }
    }

    func testLocalFilesystemRuntimeRootedRulesReadOnlyAndDeniedPrefixes() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("acp-runtime-rules-\(UUID().uuidString)", isDirectory: true)
        let readOnlyRoot = root.appendingPathComponent("readonly", isDirectory: true)
        let deniedRoot = root.appendingPathComponent("secrets", isDirectory: true)
        try FileManager.default.createDirectory(at: readOnlyRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: deniedRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let runtime = ACPLocalFilesystemRuntime(
            policy: .rootedWithRules(
                .init(
                    root: root,
                    readOnlyRoots: [readOnlyRoot],
                    deniedPathPrefixes: ["secrets"]
                )
            )
        )

        let writable = root.appendingPathComponent("writable/notes.txt").path
        _ = try await runtime.writeTextFile(.init(sessionId: "sess_rules", path: writable, content: "ok"))
        let readable = try await runtime.readTextFile(.init(sessionId: "sess_rules", path: writable))
        XCTAssertEqual(readable.content, "ok")

        let readOnlyFile = readOnlyRoot.appendingPathComponent("a.txt").path
        do {
            _ = try await runtime.writeTextFile(.init(sessionId: "sess_rules", path: readOnlyFile, content: "blocked"))
            XCTFail("Expected permission denied for read-only path")
        } catch let error as ACPRuntimeError {
            guard case .permissionDenied = error else {
                return XCTFail("Expected permission denied, got \(error)")
            }
        }

        let deniedFile = deniedRoot.appendingPathComponent("token.txt").path
        do {
            _ = try await runtime.writeTextFile(.init(sessionId: "sess_rules", path: deniedFile, content: "blocked"))
            XCTFail("Expected permission denied for denied prefix")
        } catch let error as ACPRuntimeError {
            guard case .permissionDenied = error else {
                return XCTFail("Expected permission denied, got \(error)")
            }
        }
    }

    func testProcessTerminalRuntimeLifecycle() async throws {
        let runtime = ACPProcessTerminalRuntime()

        let created = try await runtime.create(
            .init(sessionId: "sess_1", command: "/bin/sh", args: ["-c", "printf 'hello-runtime'"])
        )
        let terminalId = created.terminalId

        let waited = try await runtime.waitForExit(.init(sessionId: "sess_1", terminalId: terminalId))
        XCTAssertEqual(waited.exitCode, 0)

        var captured = ""
        for _ in 0..<10 {
            let output = try await runtime.output(.init(sessionId: "sess_1", terminalId: terminalId))
            captured = output.output
            if captured.contains("hello-runtime") {
                break
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(captured.contains("hello-runtime"), "output: \(captured)")

        _ = try await runtime.release(.init(sessionId: "sess_1", terminalId: terminalId))

        do {
            _ = try await runtime.output(.init(sessionId: "sess_1", terminalId: terminalId))
            XCTFail("Expected unknown terminal")
        } catch let error as ACPRuntimeError {
            guard case .unknownTerminal = error else {
                return XCTFail("Expected unknown terminal, got \(error)")
            }
        }
    }

    func testProcessTerminalRuntimeWaitForExitFlushesRemainingOutput() async throws {
        let runtime = ACPProcessTerminalRuntime()
        let expectedCount = 4096

        let created = try await runtime.create(
            .init(
                sessionId: "sess_flush",
                command: "/usr/bin/python3",
                args: ["-c", "import sys; sys.stdout.write('x' * \(expectedCount))"]
            )
        )

        _ = try await runtime.waitForExit(.init(sessionId: "sess_flush", terminalId: created.terminalId))
        let output = try await runtime.output(.init(sessionId: "sess_flush", terminalId: created.terminalId))
        XCTAssertEqual(output.output.count, expectedCount)
        XCTAssertTrue(output.output.allSatisfy { $0 == "x" })
        XCTAssertFalse(output.truncated)
    }

    func testProcessTerminalRuntimeRejectsDeniedCommand() async throws {
        let runtime = ACPProcessTerminalRuntime(
            policy: .init(deniedCommands: ["sh"])
        )

        do {
            _ = try await runtime.create(
                .init(sessionId: "sess_denied", command: "/bin/sh", args: ["-c", "echo hi"])
            )
            XCTFail("Expected command denied")
        } catch let error as ACPRuntimeError {
            guard case .commandDenied = error else {
                return XCTFail("Expected commandDenied, got \(error)")
            }
        }
    }

    func testProcessTerminalRuntimeTerminatesWhenExceedingMaxRuntime() async throws {
        let runtime = ACPProcessTerminalRuntime(
            policy: .init(maxRuntimeNanoseconds: 100_000_000)
        )
        let created = try await runtime.create(
            .init(sessionId: "sess_timeout", command: "/bin/sh", args: ["-c", "sleep 2"])
        )

        let start = Date()
        let waited = try await runtime.waitForExit(
            .init(sessionId: "sess_timeout", terminalId: created.terminalId)
        )
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 1.0)
        XCTAssertNotEqual(waited.exitCode, 0)
    }

    func testClientServiceInstallRuntimesHandlesIncomingRequests() async throws {
        let transport = RuntimeRequestTransport()
        let client = ACPClientService(transport: transport)
        let fs = MockFilesystemRuntime()
        let terminal = MockTerminalRuntime()

        await client.installRuntimes(filesystem: fs, terminal: terminal)
        try await client.connect()
        defer { Task { await client.close() } }

        _ = try await client.initialize(.init(protocolVersion: 1))
        try await Task.sleep(nanoseconds: 80_000_000)

        let responses = await transport.responses
        XCTAssertEqual(responses.count, 2)
        XCTAssertEqual(Set(responses.map(\.id)), Set([.string("fs-1"), .string("term-1")]))

        let fsCount = await fs.readCount
        let termCount = await terminal.createCount
        XCTAssertEqual(fsCount, 1)
        XCTAssertEqual(termCount, 1)
    }
}

private actor RuntimeRequestTransport: ACPTransport {
    private var connected = false
    private var inbox: [JSONRPCMessage] = []
    private(set) var responses: [JSONRPC.Response] = []

    func connect() async throws {
        connected = true
        let fsParams = try ACPCodec.encodeParams(
            ACPReadTextFileParams(sessionId: "sess_ops", path: "/tmp/mock.txt")
        )
        inbox.append(.request(.init(id: .string("fs-1"), method: ACPMethods.fsReadTextFile, params: fsParams)))

        let termParams = try ACPCodec.encodeParams(
            ACPTerminalCreateParams(sessionId: "sess_ops", command: "/bin/echo", args: ["hi"])
        )
        inbox.append(.request(.init(id: .string("term-1"), method: ACPMethods.terminalCreate, params: termParams)))
    }

    func send(_ message: JSONRPCMessage) async throws {
        guard connected else { throw ACPTransportError.notConnected }
        switch message {
        case .request(let request):
            if request.method == ACPMethods.initialize {
                let result = ACPInitializeResult(
                    protocolVersion: 1,
                    agentCapabilities: .init(loadSession: true),
                    agentInfo: .init(name: "runtime-agent", version: "1.0.0")
                )
                inbox.append(.response(.init(id: request.id!, result: try ACPCodec.encodeParams(result))))
            }
        case .response(let response):
            responses.append(response)
        case .notification:
            break
        }
    }

    func receive() async throws -> JSONRPCMessage? {
        guard connected else { throw ACPTransportError.notConnected }
        while inbox.isEmpty {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        return inbox.removeFirst()
    }

    func close() async {
        connected = false
    }
}

private actor MockFilesystemRuntime: ACPFilesystemRuntime {
    private(set) var readCount: Int = 0

    func readTextFile(_ params: ACPReadTextFileParams) async throws -> ACPReadTextFileResult {
        _ = params
        readCount += 1
        return .init(content: "mock")
    }

    func writeTextFile(_ params: ACPWriteTextFileParams) async throws -> ACPWriteTextFileResult {
        _ = params
        return .init()
    }
}

private actor MockTerminalRuntime: ACPTerminalRuntime {
    private(set) var createCount: Int = 0

    func create(_ params: ACPTerminalCreateParams) async throws -> ACPTerminalCreateResult {
        _ = params
        createCount += 1
        return .init(terminalId: "term_mock")
    }

    func output(_ params: ACPTerminalRefParams) async throws -> ACPTerminalOutputResult {
        _ = params
        return .init(output: "", truncated: false)
    }

    func waitForExit(_ params: ACPTerminalRefParams) async throws -> ACPTerminalWaitForExitResult {
        _ = params
        return .init(exitCode: 0, signal: nil)
    }

    func kill(_ params: ACPTerminalRefParams) async throws -> ACPTerminalKillResult {
        _ = params
        return .init()
    }

    func release(_ params: ACPTerminalRefParams) async throws -> ACPTerminalReleaseResult {
        _ = params
        return .init()
    }
}
