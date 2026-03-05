import ArgumentParser
import Foundation
import SKIACP
import SKIACPClient
import SKIACPTransport
import SKICLIShared
#if canImport(Darwin)
import Darwin
#endif

private enum TUIInputMode {
    case chat
    case setCmd
    case setArgs
    case setEndpoint
    case setCWD
    case setSessionID
}

private enum TUIRole: String {
    case user = "You"
    case assistant = "AI"
    case system = "Sys"
}

private struct TUIMessage {
    var role: TUIRole
    var text: String
}

private struct TUIConnectionConfig {
    var transport: CLITransport
    var cmd: String?
    var args: [String]
    var endpoint: String?
    var cwd: String
    var sessionID: String?
    var requestTimeoutMS: Int
    var logLevel: CLILogLevel
    var wsHeartbeatMS: Int
    var wsReconnectAttempts: Int
    var wsReconnectBaseDelayMS: Int
    var maxInFlightSends: Int
}

private enum TUISlashAction: CaseIterable {
    case connect
    case reconnect
    case disconnect
    case setTransport
    case setCmd
    case setArgs
    case setEndpoint
    case setCWD
    case setSessionID
    case newSession
    case loadSession
    case stopSession
    case clearTranscript
    case exportTranscript
    case setLogLevel

    var title: String {
        switch self {
        case .connect: return "Connect"
        case .reconnect: return "Reconnect"
        case .disconnect: return "Disconnect"
        case .setTransport: return "Set Transport"
        case .setCmd: return "Set Cmd"
        case .setArgs: return "Set Args"
        case .setEndpoint: return "Set Endpoint"
        case .setCWD: return "Set Cwd"
        case .setSessionID: return "Set Session ID"
        case .newSession: return "New Session"
        case .loadSession: return "Load Session"
        case .stopSession: return "Stop Session"
        case .clearTranscript: return "Clear Transcript"
        case .exportTranscript: return "Export Transcript"
        case .setLogLevel: return "Set Log Level"
        }
    }
}

private struct TUIState {
    var config: TUIConnectionConfig
    var messages: [TUIMessage] = []
    var input: String = ""
    var cursor: Int = 0
    var running: Bool = true
    var connected: Bool = false
    var sending: Bool = false
    var statusLine: String = "Disconnected. Input '/' for menu."
    var inputMode: TUIInputMode = .chat
    var slashVisible: Bool = false
    var slashSelected: Int = 0
    var activeAssistantIndex: Int?
    var sessionID: String?
}

private enum TUIKeyEvent {
    case character(Character)
    case enter
    case backspace
    case delete
    case left
    case right
    case up
    case down
    case esc
    case ctrlA
    case ctrlC
    case ctrlE
    case ctrlK
    case ctrlU
}

private enum SKITUIEvent {
    case key(TUIKeyEvent)
    case agentChunk(String)
    case promptFinished(String)
    case promptFailed(String)
}

private actor SKITUIEventQueue {
    private var events: [SKITUIEvent] = []

    func push(_ event: SKITUIEvent) {
        events.append(event)
    }

    func drain() -> [SKITUIEvent] {
        guard !events.isEmpty else { return [] }
        let copy = events
        events.removeAll(keepingCapacity: true)
        return copy
    }
}

private final class SKITerminalSession {
#if canImport(Darwin)
    private var originalTermios: termios?
    private var originalFlags: Int32?
#endif

    func start() throws {
#if canImport(Darwin)
        guard isatty(STDIN_FILENO) == 1, isatty(STDOUT_FILENO) == 1 else {
            throw SKICLIValidationError.invalidInput("tui requires an interactive TTY")
        }

        var term = termios()
        if tcgetattr(STDIN_FILENO, &term) != 0 {
            throw POSIXError(.EIO)
        }
        originalTermios = term

        var raw = term
        raw.c_iflag &= ~tcflag_t(BRKINT | ICRNL | INPCK | ISTRIP | IXON)
        raw.c_oflag &= ~tcflag_t(OPOST)
        raw.c_cflag |= tcflag_t(CS8)
        raw.c_lflag &= ~tcflag_t(ECHO | ICANON | IEXTEN | ISIG)

        if tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) != 0 {
            throw POSIXError(.EIO)
        }

        let flags = fcntl(STDIN_FILENO, F_GETFL, 0)
        if flags >= 0 {
            originalFlags = flags
            _ = fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK)
        }

        write("\u{001B}[?1049h")
        write("\u{001B}[?25l")
        write("\u{001B}[2J\u{001B}[H")
#else
        throw SKICLIValidationError.invalidInput("tui requires Darwin terminal support")
#endif
    }

    func stop() {
#if canImport(Darwin)
        write("\u{001B}[?25h")
        write("\u{001B}[?1049l")
        if let flags = originalFlags {
            _ = fcntl(STDIN_FILENO, F_SETFL, flags)
        }
        if var term = originalTermios {
            _ = tcsetattr(STDIN_FILENO, TCSAFLUSH, &term)
        }
#endif
    }

    func write(_ text: String) {
        let bytes = Array(text.utf8)
        var offset = 0
        while offset < bytes.count {
            let written = bytes.withUnsafeBytes { rawBuffer in
                guard let base = rawBuffer.baseAddress else { return -1 }
                let pointer = base.advanced(by: offset)
                return Darwin.write(STDOUT_FILENO, pointer, bytes.count - offset)
            }
            if written > 0 {
                offset += written
                continue
            }
            if written == -1, errno == EINTR {
                continue
            }
            if written == -1, errno == EAGAIN || errno == EWOULDBLOCK {
                usleep(1_000)
                continue
            }
            break
        }
    }

    func size() -> (width: Int, height: Int) {
#if canImport(Darwin)
        var winsize = winsize()
        if ioctl(STDOUT_FILENO, TIOCGWINSZ, &winsize) == 0 {
            let w = max(Int(winsize.ws_col), 20)
            let h = max(Int(winsize.ws_row), 8)
            return (w, h)
        }
#endif
        return (80, 24)
    }
}

private struct TUIByteParser {
    private(set) var buffer: [UInt8] = []
    private var escapeStartedAtMS: UInt64?

    mutating func append(bytes: ArraySlice<UInt8>) {
        buffer.append(contentsOf: bytes)
    }

    mutating func nextEvent(nowMS: UInt64) -> TUIKeyEvent? {
        guard let first = buffer.first else { return nil }
        if first != 0x1B {
            _ = buffer.removeFirst()
            escapeStartedAtMS = nil
            return Self.mapSingle(first)
        }

        if buffer.count >= 3, buffer[1] == 0x5B {
            let third = buffer[2]
            switch third {
            case 0x41:
                buffer.removeFirst(3)
                escapeStartedAtMS = nil
                return .up
            case 0x42:
                buffer.removeFirst(3)
                escapeStartedAtMS = nil
                return .down
            case 0x43:
                buffer.removeFirst(3)
                escapeStartedAtMS = nil
                return .right
            case 0x44:
                buffer.removeFirst(3)
                escapeStartedAtMS = nil
                return .left
            case 0x33:
                if buffer.count >= 4, buffer[3] == 0x7E {
                    buffer.removeFirst(4)
                    escapeStartedAtMS = nil
                    return .delete
                }
                return nil
            default:
                break
            }
        }

        if buffer.count >= 2 {
            _ = buffer.removeFirst()
            escapeStartedAtMS = nil
            return .esc
        }

        if escapeStartedAtMS == nil {
            escapeStartedAtMS = nowMS
            return nil
        }
        if let started = escapeStartedAtMS, nowMS >= started + 35 {
            _ = buffer.removeFirst()
            escapeStartedAtMS = nil
            return .esc
        }
        return nil
    }

    private static func mapSingle(_ byte: UInt8) -> TUIKeyEvent? {
        switch byte {
        case 0x03: return .ctrlC
        case 0x01: return .ctrlA
        case 0x05: return .ctrlE
        case 0x0B: return .ctrlK
        case 0x15: return .ctrlU
        case 0x0D, 0x0A: return .enter
        case 0x7F, 0x08: return .backspace
        case 0x20...0x7E:
            return .character(Character(UnicodeScalar(byte)))
        default:
            return nil
        }
    }
}

private final class SKITUIRuntime {
    private let terminal = SKITerminalSession()
    private let events = SKITUIEventQueue()
    private var state: TUIState
    private var previousLines: [String] = []
    private var previousWidth: Int = 0

    private var inputTask: Task<Void, Never>?
    private var client: ACPClientService?

    init(config: TUIConnectionConfig) {
        self.state = TUIState(config: config)
    }

    func run() async throws {
        do {
            try terminal.start()
        } catch let error as SKICLIValidationError {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            throw ExitCode(Int32(SKICLIExitCode.invalidInput.rawValue))
        } catch {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            throw ExitCode(Int32(SKICLIExitCode.internalError.rawValue))
        }

        defer {
            inputTask?.cancel()
            Task { await closeClient() }
            terminal.stop()
        }

        startInputLoop()
        render(force: true)

        while state.running {
            let pending = await events.drain()
            if pending.isEmpty {
                try? await Task.sleep(nanoseconds: 20_000_000)
                continue
            }
            for event in pending {
                await handle(event: event)
            }
            render(force: false)
        }
    }

    private func startInputLoop() {
        inputTask = Task.detached(priority: .userInitiated) { [events] in
#if canImport(Darwin)
            var parser = TUIByteParser()
            var bytes = [UInt8](repeating: 0, count: 128)
            while !Task.isCancelled {
                let count = read(STDIN_FILENO, &bytes, bytes.count)
                if count > 0 {
                    parser.append(bytes: bytes.prefix(Int(count)))
                    while let event = parser.nextEvent(nowMS: Self.nowMS()) {
                        await events.push(.key(event))
                    }
                } else if count < 0 && errno != EAGAIN && errno != EWOULDBLOCK {
                    break
                }
                try? await Task.sleep(nanoseconds: 10_000_000)
                while let event = parser.nextEvent(nowMS: Self.nowMS()) {
                    await events.push(.key(event))
                }
            }
#else
            _ = events
#endif
        }
    }

    private func handle(event: SKITUIEvent) async {
        switch event {
        case .key(let key):
            await handle(key: key)
        case .agentChunk(let text):
            appendAssistantChunk(text)
        case .promptFinished(let stopReason):
            state.sending = false
            state.activeAssistantIndex = nil
            state.statusLine = "Prompt finished: \(stopReason)"
        case .promptFailed(let message):
            state.sending = false
            state.activeAssistantIndex = nil
            appendSystem(message)
            state.statusLine = message
        }
    }

    private func handle(key: TUIKeyEvent) async {
        switch key {
        case .ctrlC:
            state.running = false
            return
        case .esc:
            if state.slashVisible {
                state.slashVisible = false
                state.input = ""
                state.cursor = 0
                state.statusLine = "Closed menu"
            } else if state.inputMode != .chat {
                state.inputMode = .chat
                state.input = ""
                state.cursor = 0
                state.statusLine = "Cancelled edit mode"
            } else {
                state.running = false
            }
            return
        case .up:
            if state.slashVisible {
                let actions = filteredSlashActions()
                guard !actions.isEmpty else { return }
                state.slashSelected = (state.slashSelected - 1 + actions.count) % actions.count
            }
            return
        case .down:
            if state.slashVisible {
                let actions = filteredSlashActions()
                guard !actions.isEmpty else { return }
                state.slashSelected = (state.slashSelected + 1) % actions.count
            }
            return
        case .left:
            state.cursor = max(0, state.cursor - 1)
            return
        case .right:
            state.cursor = min(state.input.count, state.cursor + 1)
            return
        case .ctrlA:
            state.cursor = 0
            return
        case .ctrlE:
            state.cursor = state.input.count
            return
        case .ctrlU:
            if state.cursor > 0 {
                state.input.removeSubrange(state.input.startIndex..<state.input.index(state.input.startIndex, offsetBy: state.cursor))
                state.cursor = 0
                updateSlashVisibility()
            }
            return
        case .ctrlK:
            if state.cursor < state.input.count {
                let cursorIdx = state.input.index(state.input.startIndex, offsetBy: state.cursor)
                state.input.removeSubrange(cursorIdx..<state.input.endIndex)
                updateSlashVisibility()
            }
            return
        case .backspace:
            guard state.cursor > 0 else { return }
            let removeIndex = state.input.index(state.input.startIndex, offsetBy: state.cursor - 1)
            state.input.remove(at: removeIndex)
            state.cursor -= 1
            updateSlashVisibility()
            return
        case .delete:
            guard state.cursor < state.input.count else { return }
            let removeIndex = state.input.index(state.input.startIndex, offsetBy: state.cursor)
            state.input.remove(at: removeIndex)
            updateSlashVisibility()
            return
        case .character(let c):
            let insertIndex = state.input.index(state.input.startIndex, offsetBy: state.cursor)
            state.input.insert(c, at: insertIndex)
            state.cursor += 1
            updateSlashVisibility()
            return
        case .enter:
            break
        }

        switch state.inputMode {
        case .chat:
            if state.slashVisible {
                let actions = filteredSlashActions()
                if actions.indices.contains(state.slashSelected) {
                    let action = actions[state.slashSelected]
                    state.input = ""
                    state.cursor = 0
                    state.slashVisible = false
                    await executeSlash(action: action)
                }
                return
            }
            await sendPromptIfPossible()
        case .setCmd, .setArgs, .setEndpoint, .setCWD, .setSessionID:
            commitInputEdit()
        }
    }

    private func filteredSlashActions() -> [TUISlashAction] {
        guard state.input.hasPrefix("/") else { return [] }
        let query = state.input.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty { return TUISlashAction.allCases }
        return TUISlashAction.allCases.filter { $0.title.lowercased().contains(query) }
    }

    private func updateSlashVisibility() {
        guard state.inputMode == .chat else {
            state.slashVisible = false
            return
        }
        if state.input.hasPrefix("/") {
            state.slashVisible = true
            let actions = filteredSlashActions()
            if actions.isEmpty {
                state.slashSelected = 0
            } else if state.slashSelected >= actions.count {
                state.slashSelected = actions.count - 1
            }
        } else {
            state.slashVisible = false
            state.slashSelected = 0
        }
    }

    private func executeSlash(action: TUISlashAction) async {
        switch action {
        case .connect:
            await connect()
        case .reconnect:
            await disconnect()
            await connect()
        case .disconnect:
            await disconnect()
        case .setTransport:
            state.config.transport = state.config.transport == .stdio ? .ws : .stdio
            state.statusLine = "Transport: \(state.config.transport.rawValue)"
        case .setCmd:
            state.inputMode = .setCmd
            state.input = state.config.cmd ?? ""
            state.cursor = state.input.count
            state.statusLine = "Edit cmd and press Enter"
        case .setArgs:
            state.inputMode = .setArgs
            state.input = state.config.args.joined(separator: " ")
            state.cursor = state.input.count
            state.statusLine = "Edit args and press Enter"
        case .setEndpoint:
            state.inputMode = .setEndpoint
            state.input = state.config.endpoint ?? ""
            state.cursor = state.input.count
            state.statusLine = "Edit endpoint and press Enter"
        case .setCWD:
            state.inputMode = .setCWD
            state.input = state.config.cwd
            state.cursor = state.input.count
            state.statusLine = "Edit cwd and press Enter"
        case .setSessionID:
            state.inputMode = .setSessionID
            state.input = state.config.sessionID ?? ""
            state.cursor = state.input.count
            state.statusLine = "Edit session ID and press Enter"
        case .newSession:
            await newSession()
        case .loadSession:
            await loadSession()
        case .stopSession:
            await stopSession()
        case .clearTranscript:
            state.messages.removeAll()
            state.statusLine = "Transcript cleared"
        case .exportTranscript:
            exportTranscript()
        case .setLogLevel:
            cycleLogLevel()
        }
    }

    private func commitInputEdit() {
        let value = state.input.trimmingCharacters(in: .whitespacesAndNewlines)
        switch state.inputMode {
        case .setCmd:
            state.config.cmd = value.isEmpty ? nil : value
            state.statusLine = "Cmd updated"
        case .setArgs:
            state.config.args = value.isEmpty ? [] : value.split(whereSeparator: \.isWhitespace).map(String.init)
            state.statusLine = "Args updated (\(state.config.args.count))"
        case .setEndpoint:
            state.config.endpoint = value.isEmpty ? nil : value
            state.statusLine = "Endpoint updated"
        case .setCWD:
            if !value.isEmpty {
                state.config.cwd = value
            }
            state.statusLine = "Cwd updated"
        case .setSessionID:
            state.config.sessionID = value.isEmpty ? nil : value
            state.statusLine = "Session ID updated"
        case .chat:
            break
        }
        state.input = ""
        state.cursor = 0
        state.inputMode = .chat
        updateSlashVisibility()
    }

    private func connect() async {
        if state.connected {
            state.statusLine = "Already connected"
            return
        }

        switch state.config.transport {
        case .stdio:
            if state.config.cmd?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                state.statusLine = "Set Cmd first via / Set Cmd"
                appendSystem("Connect failed: stdio requires cmd")
                return
            }
        case .ws:
            if state.config.endpoint?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                state.statusLine = "Set Endpoint first via / Set Endpoint"
                appendSystem("Connect failed: ws requires endpoint")
                return
            }
        }

        state.statusLine = "Connecting..."
        render(force: false)

        let requestTimeoutNanos: UInt64? = state.config.requestTimeoutMS == 0
            ? nil
            : ACPCLITransportFactory.millisecondsToNanosecondsNonNegative(state.config.requestTimeoutMS)
        let transportKind: SKICLITransportKind = state.config.transport == .ws ? .ws : .stdio
        let transportImpl: any ACPTransport
        do {
            transportImpl = try ACPCLITransportFactory.makeClientTransport(
                kind: transportKind,
                cmd: state.config.cmd,
                args: state.config.args,
                endpoint: state.config.endpoint,
                wsHeartbeatMS: state.config.wsHeartbeatMS,
                wsReconnectAttempts: state.config.wsReconnectAttempts,
                wsReconnectBaseDelayMS: state.config.wsReconnectBaseDelayMS,
                maxInFlightSends: state.config.maxInFlightSends
            )
        } catch let error as SKICLIValidationError {
            state.statusLine = error.localizedDescription
            appendSystem("Connect failed: \(error.localizedDescription)")
            return
        } catch {
            state.statusLine = error.localizedDescription
            appendSystem("Connect failed: \(error.localizedDescription)")
            return
        }

        do {
            let client = ACPClientService(transport: transportImpl, requestTimeoutNanoseconds: requestTimeoutNanos)
            let filesystemRuntime = ACPLocalFilesystemRuntime(policy: .unrestricted)
            let terminalRuntime = ACPProcessTerminalRuntime()
            let queue = events
            await client.setNotificationHandler { notification in
                guard notification.method == ACPMethods.sessionUpdate,
                      let params = try? ACPCodec.decodeParams(notification.params, as: ACPSessionUpdateParams.self) else {
                    return
                }
                if let text = params.update.content?.text, !text.isEmpty {
                    await queue.push(.agentChunk(text))
                }
            }
            await client.setPermissionRequestHandler { _ in
                ACPSessionPermissionRequestResult(
                    outcome: .selected(.init(optionId: "allow_once"))
                )
            }
            await client.installRuntimes(filesystem: filesystemRuntime, terminal: terminalRuntime)
            try await client.connect()
            _ = try await client.initialize(.init(
                protocolVersion: 1,
                clientCapabilities: .init(fs: .init(readTextFile: true, writeTextFile: true), terminal: true),
                clientInfo: .init(name: "ski", title: "SKI TUI Client", version: "0.1.0")
            ))

            let effectiveSessionID: String
            if let configured = state.config.sessionID, !configured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                effectiveSessionID = configured
            } else {
                let created = try await client.newSession(.init(cwd: state.config.cwd))
                effectiveSessionID = created.sessionId
                state.config.sessionID = created.sessionId
            }

            state.sessionID = effectiveSessionID
            state.connected = true
            state.statusLine = "Connected (\(state.config.transport.rawValue)) session=\(effectiveSessionID)"
            self.client = client
            appendSystem("Connected")
        } catch {
            state.statusLine = "Connect failed: \(error.localizedDescription)"
            appendSystem("Connect failed: \(error.localizedDescription)")
            await closeClient()
        }
    }

    private func disconnect() async {
        await closeClient()
        state.connected = false
        state.sessionID = nil
        state.sending = false
        state.activeAssistantIndex = nil
        state.statusLine = "Disconnected"
        appendSystem("Disconnected")
    }

    private func closeClient() async {
        guard let client else { return }
        await client.close()
        self.client = nil
    }

    private func newSession() async {
        guard state.connected, let client else {
            state.statusLine = "Not connected"
            return
        }
        do {
            let created = try await client.newSession(.init(cwd: state.config.cwd))
            state.sessionID = created.sessionId
            state.config.sessionID = created.sessionId
            state.statusLine = "New session: \(created.sessionId)"
            appendSystem("New session created")
        } catch {
            state.statusLine = "New session failed: \(error.localizedDescription)"
            appendSystem(state.statusLine)
        }
    }

    private func loadSession() async {
        guard state.connected, let client else {
            state.statusLine = "Not connected"
            return
        }
        guard let id = state.config.sessionID, !id.isEmpty else {
            state.statusLine = "Set session ID first"
            return
        }
        do {
            try await client.loadSession(.init(sessionId: id, cwd: state.config.cwd))
            state.sessionID = id
            state.statusLine = "Loaded session: \(id)"
            appendSystem("Loaded session \(id)")
        } catch {
            state.statusLine = "Load session failed: \(error.localizedDescription)"
            appendSystem(state.statusLine)
        }
    }

    private func stopSession() async {
        guard state.connected, let client else {
            state.statusLine = "Not connected"
            return
        }
        guard let id = state.sessionID ?? state.config.sessionID, !id.isEmpty else {
            state.statusLine = "No active session"
            return
        }
        do {
            _ = try await client.stopSession(.init(sessionId: id))
            state.statusLine = "Stopped session: \(id)"
            appendSystem("Stopped session \(id)")
            state.sessionID = nil
        } catch {
            state.statusLine = "Stop session failed: \(error.localizedDescription)"
            appendSystem(state.statusLine)
        }
    }

    private func sendPromptIfPossible() async {
        let text = state.input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard state.connected, let client else {
            state.statusLine = "Not connected, use / to connect"
            appendSystem("Prompt ignored: not connected")
            state.input = ""
            state.cursor = 0
            return
        }
        guard !state.sending else {
            state.statusLine = "Prompt in progress"
            return
        }
        guard let sessionID = state.sessionID ?? state.config.sessionID, !sessionID.isEmpty else {
            state.statusLine = "Missing session ID"
            return
        }

        state.messages.append(.init(role: .user, text: text))
        state.messages.append(.init(role: .assistant, text: ""))
        state.activeAssistantIndex = state.messages.count - 1
        state.sending = true
        state.input = ""
        state.cursor = 0
        state.statusLine = "Sending..."

        let queue = events
        Task {
            do {
                let result = try await client.prompt(.init(sessionId: sessionID, prompt: [.text(text)]))
                await queue.push(.promptFinished(result.stopReason.rawValue))
            } catch {
                await queue.push(.promptFailed("Prompt failed: \(error.localizedDescription)"))
            }
        }
    }

    private func appendAssistantChunk(_ text: String) {
        guard !text.isEmpty else { return }
        if let index = state.activeAssistantIndex, state.messages.indices.contains(index) {
            state.messages[index].text += text
            return
        }
        state.messages.append(.init(role: .assistant, text: text))
        state.activeAssistantIndex = state.messages.count - 1
    }

    private func appendSystem(_ text: String) {
        guard !text.isEmpty else { return }
        state.messages.append(.init(role: .system, text: text))
    }

    private func cycleLogLevel() {
        let all: [CLILogLevel] = [.error, .warn, .info, .debug]
        guard let index = all.firstIndex(of: state.config.logLevel) else {
            state.config.logLevel = .info
            state.statusLine = "Log level: info"
            return
        }
        let next = all[(index + 1) % all.count]
        state.config.logLevel = next
        state.statusLine = "Log level: \(next.rawValue)"
    }

    private func exportTranscript() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let filename = "ski-transcript-\(formatter.string(from: Date())).txt"
        let destination = URL(fileURLWithPath: state.config.cwd).appendingPathComponent(filename)
        let content = state.messages.map { "[\($0.role.rawValue)] \($0.text)" }.joined(separator: "\n")
        do {
            try content.write(to: destination, atomically: true, encoding: .utf8)
            state.statusLine = "Transcript exported: \(destination.path)"
            appendSystem("Transcript exported: \(destination.path)")
        } catch {
            state.statusLine = "Export failed: \(error.localizedDescription)"
            appendSystem(state.statusLine)
        }
    }

    private func render(force: Bool) {
        let size = terminal.size()
        let frame = composeFrame(width: size.width, height: size.height)

        if force || previousWidth != size.width || previousLines.count != frame.count {
            terminal.write("\u{001B}[H")
            for idx in 0..<frame.count {
                terminal.write(pad(frame[idx], width: size.width))
                if idx < frame.count - 1 {
                    terminal.write("\n")
                }
            }
        } else {
            for idx in frame.indices where frame[idx] != previousLines[idx] {
                terminal.write("\u{001B}[\(idx + 1);1H")
                terminal.write(pad(frame[idx], width: size.width))
            }
        }

        let inputRow = size.height
        let inputCol = currentInputCursorColumn(width: size.width)
        terminal.write("\u{001B}[\(inputRow);\(inputCol)H")

        previousLines = frame
        previousWidth = size.width
    }

    private func composeFrame(width: Int, height: Int) -> [String] {
        var lines: [String] = []
        let modeText: String = {
            switch state.inputMode {
            case .chat: return "chat"
            case .setCmd: return "set-cmd"
            case .setArgs: return "set-args"
            case .setEndpoint: return "set-endpoint"
            case .setCWD: return "set-cwd"
            case .setSessionID: return "set-session-id"
            }
        }()
        let sessionLabel = state.sessionID ?? "-"
        lines.append("SKI TUI | \(state.connected ? "Connected" : "Disconnected") | transport=\(state.config.transport.rawValue) | session=\(sessionLabel) | mode=\(modeText)")
        lines.append("Status: \(state.statusLine)")
        lines.append(String(repeating: "-", count: max(1, width)))

        let reserved = 5
        let bodyCapacity = max(1, height - reserved)
        var bodyLines: [String] = []
        for message in state.messages.suffix(200) {
            let prefix = "[\(message.role.rawValue)] "
            bodyLines.append(contentsOf: wrap(text: message.text, width: max(10, width - prefix.count), prefix: prefix))
        }

        if state.slashVisible {
            bodyLines.append("")
            bodyLines.append("Slash Menu (Enter execute, Esc close):")
            let actions = filteredSlashActions()
            if actions.isEmpty {
                bodyLines.append("  (no match)")
            } else {
                for (index, action) in actions.enumerated() {
                    let marker = index == state.slashSelected ? ">" : " "
                    bodyLines.append("\(marker) \(action.title)")
                }
            }
        }

        if bodyLines.count > bodyCapacity {
            bodyLines = Array(bodyLines.suffix(bodyCapacity))
        }
        lines.append(contentsOf: bodyLines)
        while lines.count < height - 2 {
            lines.append("")
        }

        lines.append(String(repeating: "-", count: max(1, width)))
        lines.append(renderInputLine(width: width))

        if lines.count > height {
            return Array(lines.prefix(height))
        }
        while lines.count < height {
            lines.append("")
        }
        return lines
    }

    private func renderInputLine(width: Int) -> String {
        let prefix = state.inputMode == .chat ? "> " : "edit> "
        let available = max(1, width - prefix.count)
        let start = max(0, state.cursor - available + 1)
        let visible = substring(state.input, from: start, length: available)
        return prefix + visible
    }

    private func currentInputCursorColumn(width: Int) -> Int {
        let prefix = state.inputMode == .chat ? 2 : 5
        let available = max(1, width - prefix)
        let start = max(0, state.cursor - available + 1)
        let col = prefix + (state.cursor - start) + 1
        return max(1, min(width, col))
    }

    private func pad(_ text: String, width: Int) -> String {
        if text.count == width { return text }
        if text.count > width { return String(text.prefix(width)) }
        return text + String(repeating: " ", count: width - text.count)
    }

    private func wrap(text: String, width: Int, prefix: String) -> [String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let rawLines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var output: [String] = []
        for raw in rawLines {
            if raw.isEmpty {
                output.append(prefix)
                continue
            }
            var remaining = raw
            var first = true
            while !remaining.isEmpty {
                let chunk = String(remaining.prefix(width))
                output.append((first ? prefix : String(repeating: " ", count: prefix.count)) + chunk)
                remaining.removeFirst(chunk.count)
                first = false
            }
        }
        return output
    }

    private func substring(_ text: String, from: Int, length: Int) -> String {
        guard !text.isEmpty, from < text.count, length > 0 else { return "" }
        let start = text.index(text.startIndex, offsetBy: max(0, from))
        let end = text.index(start, offsetBy: min(length, text.count - from), limitedBy: text.endIndex) ?? text.endIndex
        return String(text[start..<end])
    }

    private static func nowMS() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds / 1_000_000
    }
}

struct TUICommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tui",
        abstract: "Interactive terminal UI"
    )

    @Option(name: .long)
    var transport: CLITransport = .stdio

    @Option(name: .long, help: "Child executable path or command name in PATH")
    var cmd: String?

    @Option(name: .long, parsing: .upToNextOption)
    var args: [String] = []

    @Option(name: .long)
    var endpoint: String?

    @Option(name: .long, help: "Working directory sent to session/new. For ws transport, use a path valid on the server.")
    var cwd: String = FileManager.default.currentDirectoryPath

    @Option(name: .long, help: "Reuse an existing ACP session ID instead of creating a new one")
    var sessionID: String?

    @Option(name: .long, help: "Request timeout in milliseconds (0 disables)")
    var requestTimeoutMS: Int = 300_000

    @Option(name: .long)
    var logLevel: CLILogLevel = .info

    @Option(name: .long, help: "WebSocket heartbeat interval in milliseconds (0 disables)")
    var wsHeartbeatMS: Int = 15_000

    @Option(name: .long, help: "WebSocket reconnect max attempts")
    var wsReconnectAttempts: Int = 2

    @Option(name: .long, help: "WebSocket reconnect base delay in milliseconds")
    var wsReconnectBaseDelayMS: Int = 200

    @Option(name: .long, help: "Maximum in-flight websocket sends")
    var maxInFlightSends: Int = 64

    private func hasExplicitOption(_ option: String) -> Bool {
        CommandLine.arguments.contains { arg in
            arg == option || arg.hasPrefix("\(option)=")
        }
    }

    mutating func run() async throws {
        if transport == .stdio, hasExplicitOption("--endpoint") {
            fputs("Error: --endpoint is only valid for ws transport\n", stderr)
            throw ExitCode(Int32(SKICLIExitCode.invalidInput.rawValue))
        }
        if transport == .ws, cmd != nil {
            fputs("Error: --cmd is only valid for stdio transport\n", stderr)
            throw ExitCode(Int32(SKICLIExitCode.invalidInput.rawValue))
        }
        if transport == .ws, !args.isEmpty {
            fputs("Error: --args is only valid for stdio transport\n", stderr)
            throw ExitCode(Int32(SKICLIExitCode.invalidInput.rawValue))
        }
        if requestTimeoutMS < 0 {
            fputs("Error: --request-timeout-ms must be >= 0\n", stderr)
            throw ExitCode(Int32(SKICLIExitCode.invalidInput.rawValue))
        }
        if wsHeartbeatMS < 0 {
            fputs("Error: --ws-heartbeat-ms must be >= 0\n", stderr)
            throw ExitCode(Int32(SKICLIExitCode.invalidInput.rawValue))
        }
        if wsReconnectAttempts < 0 {
            fputs("Error: --ws-reconnect-attempts must be >= 0\n", stderr)
            throw ExitCode(Int32(SKICLIExitCode.invalidInput.rawValue))
        }
        if wsReconnectBaseDelayMS < 0 {
            fputs("Error: --ws-reconnect-base-delay-ms must be >= 0\n", stderr)
            throw ExitCode(Int32(SKICLIExitCode.invalidInput.rawValue))
        }
        if maxInFlightSends <= 0 {
            fputs("Error: --max-in-flight-sends must be > 0\n", stderr)
            throw ExitCode(Int32(SKICLIExitCode.invalidInput.rawValue))
        }
        if let sessionID, sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fputs("Error: --session-id must not be empty when provided\n", stderr)
            throw ExitCode(Int32(SKICLIExitCode.invalidInput.rawValue))
        }

        guard isInteractiveTTY() else {
            fputs("Error: tui requires an interactive TTY\n", stderr)
            throw ExitCode(Int32(SKICLIExitCode.invalidInput.rawValue))
        }

        let config = TUIConnectionConfig(
            transport: transport,
            cmd: cmd,
            args: args,
            endpoint: endpoint,
            cwd: cwd,
            sessionID: sessionID,
            requestTimeoutMS: requestTimeoutMS,
            logLevel: logLevel,
            wsHeartbeatMS: wsHeartbeatMS,
            wsReconnectAttempts: wsReconnectAttempts,
            wsReconnectBaseDelayMS: wsReconnectBaseDelayMS,
            maxInFlightSends: maxInFlightSends
        )
        try await SKITUIRuntime(config: config).run()
    }
}

private func isInteractiveTTY() -> Bool {
#if canImport(Darwin)
    return isatty(STDIN_FILENO) == 1 && isatty(STDOUT_FILENO) == 1
#else
    return false
#endif
}

func runSKIDefaultChatMode() async throws {
    guard isInteractiveTTY() else {
        fputs("Error: ski defaults to chat mode and requires an interactive TTY; use 'ski acp ...' in non-interactive environments\n", stderr)
        throw ExitCode(Int32(SKICLIExitCode.invalidInput.rawValue))
    }
    let config = TUIConnectionConfig(
        transport: .stdio,
        cmd: nil,
        args: [],
        endpoint: nil,
        cwd: FileManager.default.currentDirectoryPath,
        sessionID: nil,
        requestTimeoutMS: 300_000,
        logLevel: .info,
        wsHeartbeatMS: 15_000,
        wsReconnectAttempts: 2,
        wsReconnectBaseDelayMS: 200,
        maxInFlightSends: 64
    )
    try await SKITUIRuntime(config: config).run()
}
