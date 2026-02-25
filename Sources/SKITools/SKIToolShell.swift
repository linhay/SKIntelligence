import Foundation
import JSONSchemaBuilder
import SKIntelligence
#if canImport(SKProcessRunner)
import SKProcessRunner
#endif

/// `shell` tool: runs a whitelisted executable with arguments.
///
/// This tool is intentionally conservative:
/// - No interactive shell by default (no `zsh -lc <script>`).
/// - Executable must be in the allowlist.
/// - Optional working directory must be under allowed roots.
/// - Output is capped to avoid huge tool responses.
public struct SKIToolShell: SKITool {

    public var name: String = "shell"
    public var shortDescription: String = "安全 Shell 执行（allowlist）"
    public var description: String =
        """
        在本进程内执行一个允许的命令（可选 cwd/env/timeout），返回 stdout/stderr/exitCode。
        注意：默认只允许 allowlist 内的可执行文件；可选地通过配置允许 zsh script。
        """

    @Schemable
    public struct Arguments: Codable {
        public let command: [String]?
        public let script: String?
        public let cwd: String?
        public let env: [String]?
        public let timeoutMs: Int?

        public init(
            command: [String]? = nil,
            script: String? = nil,
            cwd: String? = nil,
            env: [String]? = nil,
            timeoutMs: Int? = nil
        ) {
            self.command = command
            self.script = script
            self.cwd = cwd
            self.env = env
            self.timeoutMs = timeoutMs
        }
    }

    @Schemable
    public struct ToolOutput: Codable, Sendable, Equatable {
        public let stdout: String
        public let stderr: String
        public let exitCode: Int
        public let timedOut: Bool
        public let truncated: Bool

        public init(
            stdout: String,
            stderr: String,
            exitCode: Int,
            timedOut: Bool,
            truncated: Bool
        ) {
            self.stdout = stdout
            self.stderr = stderr
            self.exitCode = exitCode
            self.timedOut = timedOut
            self.truncated = truncated
        }
    }

    public struct Configuration: Sendable, Equatable {
        /// When true, allows running any executable path provided by the caller.
        /// When false (default), only executables whose basename is included in `allowedExecutables` are permitted.
        public var allowAllExecutables: Bool
        public var allowedExecutables: Set<String>
        public var allowedRoots: [URL]
        public var allowScript: Bool
        public var maxOutputBytes: Int
        public var defaultTimeoutMs: Int

        public init(
            allowAllExecutables: Bool = false,
            allowedExecutables: Set<String>,
            allowedRoots: [URL],
            allowScript: Bool = false,
            maxOutputBytes: Int = 64 * 1024,
            defaultTimeoutMs: Int = 12_000
        ) {
            self.allowAllExecutables = allowAllExecutables
            self.allowedExecutables = allowedExecutables
            self.allowedRoots = allowedRoots
            self.allowScript = allowScript
            self.maxOutputBytes = maxOutputBytes
            self.defaultTimeoutMs = defaultTimeoutMs
        }
    }

    private let configuration: Configuration

    public init(configuration: Configuration = .defaultForCurrentProcess()) {
        self.configuration = configuration
    }

    public static var isRuntimeSupported: Bool {
#if canImport(SKProcessRunner)
        return true
#else
        return false
#endif
    }

    public func displayName(for arguments: Arguments) async -> String {
        if let cmd = arguments.command?.first, !cmd.isEmpty {
            return "Shell [\(cmd)]"
        }
        if let script = arguments.script?.trimmingCharacters(in: .whitespacesAndNewlines), !script.isEmpty {
            return "Shell Script"
        }
        return "Shell"
    }

    public func call(_ arguments: Arguments) async throws -> ToolOutput {
        guard Self.isRuntimeSupported else {
            throw SKIToolError.toolUnavailable(name: "shell (SKProcessRunner unavailable on this platform)")
        }

        let timeoutMs = max(1_000, min(arguments.timeoutMs ?? configuration.defaultTimeoutMs, 120_000))
        let env = parseEnv(arguments.env ?? [])
        let cwd = try resolveCwd(arguments.cwd)

        let (execURL, execName, execArgs) = try resolveExecution(arguments: arguments, cwd: cwd)
        guard configuration.allowAllExecutables || configuration.allowedExecutables.contains(execName) else {
            throw SKIToolError.permissionDenied("Executable is not allowed: \(execName)")
        }

#if canImport(SKProcessRunner)
        let result: SKProcessResult
        do {
            let payload = SKProcessPayload(
                executable: .url(execURL),
                arguments: execArgs,
                stdinData: nil,
                cwd: cwd,
                environment: SKProcessEnvironment(env),
                useUserShellEnvironment: false,
                userShellPath: nil,
                userShellMode: .loginInteractive,
                userShellTimeoutMs: 2_000,
                timeoutMs: timeoutMs,
                maxOutputBytes: configuration.maxOutputBytes,
                throwOnNonZeroExit: false,
                pty: nil
            )
            result = try await SKProcessRunner.run(payload)
        } catch let error as SKProcessRunError {
            switch error {
            case .timedOut(_, let stdoutData, let stderrData, let truncated):
                return ToolOutput(
                    stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                    stderr: String(data: stderrData, encoding: .utf8) ?? "",
                    exitCode: -1,
                    timedOut: true,
                    truncated: truncated
                )
            case .executableNotFound, .invalidExecutable:
                throw SKIToolError.invalidArguments(error.localizedDescription)
            case .nonZeroExit:
                // This should never happen because we don't throw on non-zero exit for this tool.
                throw SKIToolError.executionFailed(reason: error.localizedDescription)
            case .ptyFailed:
                throw SKIToolError.executionFailed(reason: error.localizedDescription)
            }
        } catch {
            throw SKIToolError.executionFailed(reason: String(describing: error))
        }

        return ToolOutput(
            stdout: result.stdout,
            stderr: result.stderr,
            exitCode: result.exitCode,
            timedOut: result.timedOut,
            truncated: result.truncated
        )
#else
        _ = timeoutMs
        _ = env
        _ = cwd
        _ = execURL
        _ = execArgs
        throw SKIToolError.toolUnavailable(name: "shell (SKProcessRunner unavailable on this platform)")
#endif
    }

    private func resolveExecution(arguments: Arguments, cwd: URL?) throws -> (URL, String, [String]) {
        if let command = arguments.command, !command.isEmpty {
            let exec = command[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !exec.isEmpty else { throw SKIToolError.invalidArguments("command[0] must be non-empty.") }

            if exec.contains("/") {
                let execURL: URL
                if exec.hasPrefix("/") {
                    execURL = URL(fileURLWithPath: exec).standardizedFileURL
                } else {
                    let base = (cwd ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true))
                        .standardizedFileURL
                    execURL = base.appendingPathComponent(exec).standardizedFileURL
                }
                return (execURL, execURL.lastPathComponent, Array(command.dropFirst()))
            }

            guard let execURL = resolveExecutableInPath(named: exec) else {
                throw SKIToolError.invalidArguments("Executable not found in PATH: \(exec)")
            }
            return (execURL, exec, Array(command.dropFirst()))
        }

        if let script = arguments.script?.trimmingCharacters(in: .whitespacesAndNewlines),
           !script.isEmpty {
            guard configuration.allowScript else {
                throw SKIToolError.permissionDenied("script execution is disabled.")
            }
            let zsh = URL(fileURLWithPath: "/bin/zsh")
            return (zsh, "zsh", ["-lc", script])
        }

        throw SKIToolError.invalidArguments("Provide either `command` or `script`.")
    }

    private func parseEnv(_ pairs: [String]) -> [String: String] {
        var out: [String: String] = [:]
        for pair in pairs {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let key = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(parts[1])
            guard !key.isEmpty else { continue }
            out[key] = value
        }
        return out
    }

    private func resolveCwd(_ value: String?) throws -> URL? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        let url: URL
        if value.hasPrefix("/") {
            url = URL(fileURLWithPath: value, isDirectory: true).standardizedFileURL
        } else {
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true).standardizedFileURL
            url = cwd.appendingPathComponent(value, isDirectory: true).standardizedFileURL
        }

        guard isAllowed(url: url) else {
            throw SKIToolError.permissionDenied("cwd is not allowed: \(value)")
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            throw SKIToolError.invalidArguments("cwd does not exist or is not a directory: \(value)")
        }
        return url
    }

    private func isAllowed(url: URL) -> Bool {
        let standardized = url.standardizedFileURL
        for root in configuration.allowedRoots {
            let r = root.standardizedFileURL
            if standardized.path == r.path { return true }
            if standardized.path.hasPrefix(r.path + "/") { return true }
        }
        return false
    }
}

private func resolveExecutableInPath(named name: String) -> URL? {
#if canImport(SKProcessRunner)
    return SKProcessRunner.resolveExecutableInPath(named: name)
#else
    _ = name
    return nil
#endif
}

extension SKIToolShell.Configuration {
    public static func defaultForCurrentProcess() -> Self {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true).standardizedFileURL
        let parent = cwd.deletingLastPathComponent()

        // Very small allowlist by default. Expand via injected Configuration.
        let allowed: Set<String> = [
            "echo",
            "pwd",
            "whoami",
            "date",
            "uname",
        ]

        return .init(
            allowedExecutables: allowed,
            allowedRoots: Array(Set([cwd, parent].map { $0.standardizedFileURL }))
        )
    }
}
