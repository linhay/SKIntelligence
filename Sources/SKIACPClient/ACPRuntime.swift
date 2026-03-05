import Foundation
import SKIACP
import SKIACPTransport
#if canImport(SKProcessRunner)
import SKProcessRunner
#endif

public enum ACPRuntimeError: Error, LocalizedError, Equatable {
    case permissionDenied(path: String)
    case unknownTerminal(String)
    case commandDenied(String)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied(let path):
            return "Permission denied: \(path)"
        case .unknownTerminal(let terminalId):
            return "Unknown terminalId: \(terminalId)"
        case .commandDenied(let command):
            return "Command denied: \(command)"
        }
    }
}

/// Non-ACP extension point.
/// Runtime abstractions are local implementation hooks behind ACP client methods,
/// not new ACP schema methods or payload fields.
public protocol ACPFilesystemRuntime: Sendable {
    func readTextFile(_ params: ACPReadTextFileParams) async throws -> ACPReadTextFileResult
    func writeTextFile(_ params: ACPWriteTextFileParams) async throws -> ACPWriteTextFileResult
}

/// Non-ACP extension point.
/// Access policy is enforced locally by runtime and must not be serialized into ACP payload.
public enum ACPFilesystemAccessPolicy: Sendable, Equatable {
    case unrestricted
    case rooted(URL)
    case rootedWithRules(ACPFilesystemRootedRules)
}

/// Non-ACP extension policy model for local filesystem runtime.
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

/// Local runtime implementation for ACP `fs/*` methods.
/// This type belongs to implementation layer, not ACP protocol schema.
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

/// Non-ACP extension point.
/// Runtime abstraction for handling ACP `terminal/*` methods in-process.
public protocol ACPTerminalRuntime: Sendable {
    func create(_ params: ACPTerminalCreateParams) async throws -> ACPTerminalCreateResult
    func output(_ params: ACPTerminalRefParams) async throws -> ACPTerminalOutputResult
    func waitForExit(_ params: ACPTerminalRefParams) async throws -> ACPTerminalWaitForExitResult
    func kill(_ params: ACPTerminalRefParams) async throws -> ACPTerminalKillResult
    func release(_ params: ACPTerminalRefParams) async throws -> ACPTerminalReleaseResult
}

/// Local runtime implementation for ACP `terminal/*` methods.
/// Policy and process lifecycle are implementation details outside ACP schema.
public actor ACPProcessTerminalRuntime: ACPTerminalRuntime {
    public struct Policy: Sendable, Equatable {
        public var allowedCommands: Set<String>?
        public var deniedCommands: Set<String>
        public var maxRuntimeNanoseconds: UInt64?

        public init(
            allowedCommands: Set<String>? = nil,
            deniedCommands: Set<String> = [],
            maxRuntimeNanoseconds: UInt64? = nil
        ) {
            self.allowedCommands = allowedCommands
            self.deniedCommands = deniedCommands
            self.maxRuntimeNanoseconds = maxRuntimeNanoseconds
        }
    }

#if os(iOS) || os(tvOS) || os(watchOS)
    public static let isRuntimeSupported = false

    public init(policy: Policy = .init()) {
        _ = policy
    }

    public func create(_ params: ACPTerminalCreateParams) async throws -> ACPTerminalCreateResult {
        _ = params
        throw ACPTransportError.unsupported("Terminal runtime is unavailable on this platform")
    }

    public func output(_ params: ACPTerminalRefParams) async throws -> ACPTerminalOutputResult {
        _ = params
        throw ACPTransportError.unsupported("Terminal runtime is unavailable on this platform")
    }

    public func waitForExit(_ params: ACPTerminalRefParams) async throws -> ACPTerminalWaitForExitResult {
        _ = params
        throw ACPTransportError.unsupported("Terminal runtime is unavailable on this platform")
    }

    public func kill(_ params: ACPTerminalRefParams) async throws -> ACPTerminalKillResult {
        _ = params
        throw ACPTransportError.unsupported("Terminal runtime is unavailable on this platform")
    }

    public func release(_ params: ACPTerminalRefParams) async throws -> ACPTerminalReleaseResult {
        _ = params
        throw ACPTransportError.unsupported("Terminal runtime is unavailable on this platform")
    }
#else
    private struct Entry {
#if canImport(SKProcessRunner)
        let session: SKProcessPipeSession
        var stdoutTask: Task<Void, Never>?
        var stderrTask: Task<Void, Never>?
        var waitTask: Task<Void, Never>?
#endif
        var output: String
        var truncated: Bool
        let limit: Int?
        var didExit: Bool
        var terminationStatus: Int32
        var waiters: [CheckedContinuation<ACPTerminalWaitForExitResult, Error>]
    }

    private var entries: [String: Entry] = [:]
    private var timeoutTasks: [String: Task<Void, Never>] = [:]
    private let policy: Policy

    public static let isRuntimeSupported = true

    public init(policy: Policy = .init()) {
        self.policy = policy
    }

    public func create(_ params: ACPTerminalCreateParams) async throws -> ACPTerminalCreateResult {
        try validateCommand(params.command)
#if canImport(SKProcessRunner)
        var environment = ProcessInfo.processInfo.environment
        for item in params.env {
            environment[item.name] = item.value
        }
        let payload = SKProcessPayload(
            executable: .url(URL(fileURLWithPath: params.command)),
            arguments: params.args,
            stdinData: nil,
            cwd: params.cwd.map { URL(fileURLWithPath: $0) },
            environment: SKProcessEnvironment(environment),
            useUserShellEnvironment: false,
            userShellPath: nil,
            userShellMode: .loginInteractive,
            userShellTimeoutMs: 2_000,
            timeoutMs: 30 * 60 * 1_000,
            maxOutputBytes: max(8 * 1_024, min(params.outputByteLimit ?? 64 * 1_024, 2 * 1_024 * 1_024)),
            terminationGracePeriodMs: 300,
            spoolFullOutput: false,
            fullOutputDirectory: nil,
            throwOnNonZeroExit: false,
            pty: nil
        )
        let session = try SKProcessPipeSession(payload)
        let terminalID = "term_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        entries[terminalID] = Entry(
            session: session,
            stdoutTask: nil,
            stderrTask: nil,
            waitTask: nil,
            output: "",
            truncated: false,
            limit: params.outputByteLimit,
            didExit: false,
            terminationStatus: 0,
            waiters: []
        )

        let stdoutTask = Task { [weak self] in
            let stream = await session.stdout
            for await chunk in stream {
                await self?.appendOutput(chunk, terminalID: terminalID)
            }
        }
        let stderrTask = Task { [weak self] in
            let stream = await session.stderr
            for await chunk in stream {
                await self?.appendOutput(chunk, terminalID: terminalID)
            }
        }
        let waitTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await session.wait()
                await self.markExit(
                    terminalID: terminalID,
                    status: Int32(result.exitCode),
                    finalOutputData: result.stdoutData + result.stderrData,
                    truncatedOverride: result.truncated
                )
            } catch let error as SKProcessRunError {
                switch error {
                case .timedOut(_, let stdoutData, let stderrData, let truncated):
                    await self.markExit(
                        terminalID: terminalID,
                        status: -1,
                        finalOutputData: stdoutData + stderrData,
                        truncatedOverride: truncated
                    )
                default:
                    await self.markExit(terminalID: terminalID, status: -1, finalOutputData: nil, truncatedOverride: nil)
                }
            } catch {
                await self.markExit(terminalID: terminalID, status: -1, finalOutputData: nil, truncatedOverride: nil)
            }
        }
        if var entry = entries[terminalID] {
            entry.stdoutTask = stdoutTask
            entry.stderrTask = stderrTask
            entry.waitTask = waitTask
            entries[terminalID] = entry
        }
        scheduleTimeoutIfNeeded(terminalID: terminalID)
        return .init(terminalId: terminalID)
#else
        _ = params
        throw ACPTransportError.unsupported("Terminal runtime is unavailable on this platform")
#endif
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
#if canImport(SKProcessRunner)
        if !entry.didExit {
            await entry.session.terminate()
        }
#endif
        return .init()
    }

    public func release(_ params: ACPTerminalRefParams) async throws -> ACPTerminalReleaseResult {
        guard let entry = entries.removeValue(forKey: params.terminalId) else {
            throw ACPRuntimeError.unknownTerminal(params.terminalId)
        }
        timeoutTasks[params.terminalId]?.cancel()
        timeoutTasks[params.terminalId] = nil
#if canImport(SKProcessRunner)
        entry.stdoutTask?.cancel()
        entry.stderrTask?.cancel()
        entry.waitTask?.cancel()
        if !entry.didExit {
            await entry.session.terminate()
        }
#endif
        if !entry.didExit {
            for waiter in entry.waiters {
                waiter.resume(throwing: ACPTransportError.eof)
            }
        }
        return .init()
    }

    private func appendOutput(_ data: Data, terminalID: String) {
        guard var entry = entries[terminalID] else { return }
        appendOutputData(data, to: &entry, replace: false)
        entries[terminalID] = entry
    }

    private func markExit(
        terminalID: String,
        status: Int32,
        finalOutputData: Data?,
        truncatedOverride: Bool?
    ) {
        guard var entry = entries[terminalID] else { return }
        guard !entry.didExit else { return }
        timeoutTasks[terminalID]?.cancel()
        timeoutTasks[terminalID] = nil
#if canImport(SKProcessRunner)
        entry.stdoutTask?.cancel()
        entry.stderrTask?.cancel()
#endif
        if let finalOutputData {
            appendOutputData(finalOutputData, to: &entry, replace: true)
        }
        if let truncatedOverride {
            entry.truncated = entry.truncated || truncatedOverride
        }
        entry.didExit = true
        entry.terminationStatus = status
        let waiters = entry.waiters
        entry.waiters.removeAll()
        entries[terminalID] = entry
        for waiter in waiters {
            waiter.resume(returning: .init(exitCode: Int(status), signal: nil))
        }
    }

    private func appendOutputData(_ data: Data, to entry: inout Entry, replace: Bool) {
        if replace {
            entry.output = ""
            entry.truncated = false
        }
        let chunk = String(decoding: data, as: UTF8.self)
        entry.output += chunk
        if let limit = entry.limit, limit >= 0 {
            while entry.output.utf8.count > limit {
                entry.truncated = true
                entry.output.removeFirst()
            }
        }
    }

    private func validateCommand(_ command: String) throws {
        let executable = URL(fileURLWithPath: command).lastPathComponent
        if policy.deniedCommands.contains(executable) || policy.deniedCommands.contains(command) {
            throw ACPRuntimeError.commandDenied(command)
        }
        if let allowed = policy.allowedCommands, !allowed.contains(executable), !allowed.contains(command) {
            throw ACPRuntimeError.commandDenied(command)
        }
    }

    private func scheduleTimeoutIfNeeded(terminalID: String) {
        guard let timeout = policy.maxRuntimeNanoseconds else { return }
        let task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: timeout)
            await self?.terminateIfRunning(terminalID: terminalID)
        }
        timeoutTasks[terminalID] = task
    }

    private func terminateIfRunning(terminalID: String) async {
        guard let entry = entries[terminalID], !entry.didExit else { return }
#if canImport(SKProcessRunner)
        await entry.session.terminate()
#endif
    }
#endif
}
