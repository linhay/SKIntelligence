import Foundation
import SKIACP
import SKIACPTransport

public enum ACPRuntimeError: Error, LocalizedError, Equatable {
    case permissionDenied(path: String)
    case unknownTerminal(String)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied(let path):
            return "Permission denied: \(path)"
        case .unknownTerminal(let terminalId):
            return "Unknown terminalId: \(terminalId)"
        }
    }
}

public protocol ACPFilesystemRuntime: Sendable {
    func readTextFile(_ params: ACPReadTextFileParams) async throws -> ACPReadTextFileResult
    func writeTextFile(_ params: ACPWriteTextFileParams) async throws -> ACPWriteTextFileResult
}

public enum ACPFilesystemAccessPolicy: Sendable, Equatable {
    case unrestricted
    case rooted(URL)
    case rootedWithRules(ACPFilesystemRootedRules)
}

public struct ACPFilesystemRootedRules: Sendable, Equatable {
    public var root: URL
    public var readOnlyRoots: [URL]
    public var deniedPathPrefixes: [String]

    public init(
        root: URL,
        readOnlyRoots: [URL] = [],
        deniedPathPrefixes: [String] = []
    ) {
        self.root = root
        self.readOnlyRoots = readOnlyRoots
        self.deniedPathPrefixes = deniedPathPrefixes
    }
}

public struct ACPLocalFilesystemRuntime: ACPFilesystemRuntime {
    private let policy: ACPFilesystemAccessPolicy

    public init(policy: ACPFilesystemAccessPolicy = .unrestricted) {
        self.policy = policy
    }

    public func readTextFile(_ params: ACPReadTextFileParams) async throws -> ACPReadTextFileResult {
        let url = try resolve(path: params.path, forWrite: false)
        let content = try String(contentsOf: url, encoding: .utf8)

        guard let line = params.line, let limit = params.limit else {
            return .init(content: content)
        }

        let lines = content.components(separatedBy: .newlines)
        let start = max(0, line - 1)
        let end = min(lines.count, start + max(0, limit))
        if start >= end {
            return .init(content: "")
        }
        return .init(content: lines[start..<end].joined(separator: "\n"))
    }

    public func writeTextFile(_ params: ACPWriteTextFileParams) async throws -> ACPWriteTextFileResult {
        let url = try resolve(path: params.path, forWrite: true)
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try params.content.write(to: url, atomically: true, encoding: .utf8)
        return .init()
    }

    private func resolve(path: String, forWrite: Bool) throws -> URL {
        let url = URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            .standardizedFileURL
        try validate(url: url, forWrite: forWrite)
        return url
    }

    private func validate(url: URL, forWrite: Bool) throws {
        let root: URL
        let readOnlyRoots: [URL]
        let deniedPathPrefixes: [String]
        switch policy {
        case .unrestricted:
            return
        case .rooted(let rootURL):
            root = rootURL
            readOnlyRoots = []
            deniedPathPrefixes = []
        case .rootedWithRules(let rules):
            root = rules.root
            readOnlyRoots = rules.readOnlyRoots
            deniedPathPrefixes = rules.deniedPathPrefixes
        }

        let rootResolved = root.standardizedFileURL.resolvingSymlinksInPath()

        let targetURL: URL
        if forWrite, !FileManager.default.fileExists(atPath: url.path) {
            targetURL = url.deletingLastPathComponent()
        } else {
            targetURL = url
        }

        let candidate = targetURL.standardizedFileURL.resolvingSymlinksInPath().path
        let rootPath = rootResolved.path
        if candidate == rootPath || candidate.hasPrefix(rootPath + "/") {
            // continue
        } else {
            throw ACPRuntimeError.permissionDenied(path: url.path)
        }

        for prefix in deniedPathPrefixes where !prefix.isEmpty {
            let normalized = prefix.hasPrefix("/") ? prefix : "/" + prefix
            if candidate == rootPath + normalized || candidate.hasPrefix(rootPath + normalized + "/") {
                throw ACPRuntimeError.permissionDenied(path: url.path)
            }
        }

        guard forWrite else { return }
        for readOnlyRoot in readOnlyRoots {
            let resolved = readOnlyRoot.standardizedFileURL.resolvingSymlinksInPath().path
            if candidate == resolved || candidate.hasPrefix(resolved + "/") {
                throw ACPRuntimeError.permissionDenied(path: url.path)
            }
        }
    }
}

public protocol ACPTerminalRuntime: Sendable {
    func create(_ params: ACPTerminalCreateParams) async throws -> ACPTerminalCreateResult
    func output(_ params: ACPTerminalRefParams) async throws -> ACPTerminalOutputResult
    func waitForExit(_ params: ACPTerminalRefParams) async throws -> ACPTerminalWaitForExitResult
    func kill(_ params: ACPTerminalRefParams) async throws -> ACPTerminalKillResult
    func release(_ params: ACPTerminalRefParams) async throws -> ACPTerminalReleaseResult
}

public actor ACPProcessTerminalRuntime: ACPTerminalRuntime {
    private struct Entry {
        let process: Process
        let stdout: Pipe
        var output: String
        var truncated: Bool
        let limit: Int?
        var didExit: Bool
        var terminationStatus: Int32
        var waiters: [CheckedContinuation<ACPTerminalWaitForExitResult, Error>]
    }

    private var entries: [String: Entry] = [:]

    public init() {}

    public func create(_ params: ACPTerminalCreateParams) async throws -> ACPTerminalCreateResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: params.command)
        process.arguments = params.args
        if let cwd = params.cwd {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }
        if !params.env.isEmpty {
            var env = ProcessInfo.processInfo.environment
            for item in params.env {
                env[item.name] = item.value
            }
            process.environment = env
        }

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = stdout

        let terminalID = "term_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        entries[terminalID] = Entry(
            process: process,
            stdout: stdout,
            output: "",
            truncated: false,
            limit: params.outputByteLimit,
            didExit: false,
            terminationStatus: 0,
            waiters: []
        )

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { await self?.appendOutput(data, terminalID: terminalID) }
        }

        process.terminationHandler = { [weak self] proc in
            Task { await self?.markExit(terminalID: terminalID, status: proc.terminationStatus) }
        }

        try process.run()
        return .init(terminalId: terminalID)
    }

    public func output(_ params: ACPTerminalRefParams) async throws -> ACPTerminalOutputResult {
        guard let entry = entries[params.terminalId] else {
            throw ACPRuntimeError.unknownTerminal(params.terminalId)
        }
        let exitStatus = entry.didExit ? ACPTerminalExitStatus(exitCode: Int(entry.terminationStatus), signal: nil) : nil
        return .init(output: entry.output, truncated: entry.truncated, exitStatus: exitStatus)
    }

    public func waitForExit(_ params: ACPTerminalRefParams) async throws -> ACPTerminalWaitForExitResult {
        guard var entry = entries[params.terminalId] else {
            throw ACPRuntimeError.unknownTerminal(params.terminalId)
        }
        if entry.didExit {
            return .init(exitCode: Int(entry.terminationStatus), signal: nil)
        }
        return try await withCheckedThrowingContinuation { continuation in
            entry.waiters.append(continuation)
            entries[params.terminalId] = entry
        }
    }

    public func kill(_ params: ACPTerminalRefParams) async throws -> ACPTerminalKillResult {
        guard let entry = entries[params.terminalId] else {
            throw ACPRuntimeError.unknownTerminal(params.terminalId)
        }
        if entry.process.isRunning {
            entry.process.terminate()
        }
        return .init()
    }

    public func release(_ params: ACPTerminalRefParams) async throws -> ACPTerminalReleaseResult {
        guard let entry = entries.removeValue(forKey: params.terminalId) else {
            throw ACPRuntimeError.unknownTerminal(params.terminalId)
        }
        entry.stdout.fileHandleForReading.readabilityHandler = nil
        if !entry.didExit {
            for waiter in entry.waiters {
                waiter.resume(throwing: ACPTransportError.eof)
            }
        }
        return .init()
    }

    private func appendOutput(_ data: Data, terminalID: String) {
        guard var entry = entries[terminalID] else { return }
        let chunk = String(decoding: data, as: UTF8.self)
        entry.output += chunk
        if let limit = entry.limit, limit >= 0 {
            while entry.output.utf8.count > limit {
                entry.truncated = true
                entry.output.removeFirst()
            }
        }
        entries[terminalID] = entry
    }

    private func markExit(terminalID: String, status: Int32) {
        guard var entry = entries[terminalID] else { return }
        entry.didExit = true
        entry.terminationStatus = status
        let waiters = entry.waiters
        entry.waiters.removeAll()
        entries[terminalID] = entry
        for waiter in waiters {
            waiter.resume(returning: .init(exitCode: Int(status), signal: nil))
        }
    }
}
