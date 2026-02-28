import Foundation
import SKIACP

public enum WebSocketIncomingMessage: Sendable, Equatable {
    case string(String)
    case data(Data)
}

public protocol WebSocketConnection: Sendable {
    func send(text: String) async throws
    func receive() async throws -> WebSocketIncomingMessage
    func sendPing() async throws
    func close() async
}

public protocol WebSocketConnectionFactory: Sendable {
    func make(endpoint: URL, headers: [String: String]) async throws -> any WebSocketConnection
}

public actor WebSocketClientTransport: ACPTransport {
    public struct Options: Sendable, Equatable {
        public var heartbeatIntervalNanoseconds: UInt64?
        public var retryPolicy: ACPTransportRetryPolicy
        public var maxInFlightSends: Int

        public init(
            heartbeatIntervalNanoseconds: UInt64? = 15_000_000_000,
            retryPolicy: ACPTransportRetryPolicy = .init(maxAttempts: 2),
            maxInFlightSends: Int = 64
        ) {
            self.heartbeatIntervalNanoseconds = heartbeatIntervalNanoseconds
            self.retryPolicy = retryPolicy
            self.maxInFlightSends = max(1, maxInFlightSends)
        }
    }

    private let endpoint: URL
    private let headers: [String: String]
    private let options: Options
    private let connectionFactory: any WebSocketConnectionFactory
    private let framer = JSONRPCLineFramer()
    private let gate: ACPTransportBackpressureGate

    private var connection: (any WebSocketConnection)?
    private var heartbeatTask: Task<Void, Never>?
    private var closed = false

    public init(endpoint: URL, headers: [String: String] = [:], options: Options = .init()) {
        self.endpoint = endpoint
        self.headers = headers
        self.options = options
        self.connectionFactory = URLSessionWebSocketConnectionFactory()
        self.gate = ACPTransportBackpressureGate(maxInFlight: options.maxInFlightSends)
    }

    init(
        endpoint: URL,
        headers: [String: String] = [:],
        options: Options = .init(),
        connectionFactory: any WebSocketConnectionFactory
    ) {
        self.endpoint = endpoint
        self.headers = headers
        self.options = options
        self.connectionFactory = connectionFactory
        self.gate = ACPTransportBackpressureGate(maxInFlight: options.maxInFlightSends)
    }

    public func connect() async throws {
        if connection != nil { return }
        closed = false
        try await reconnect(force: true)
    }

    public func send(_ message: JSONRPCMessage) async throws {
        try ensureConnected()
        await gate.acquire()
        defer { Task { await gate.release() } }

        let data = try JSONRPCCodec.encode(message)
        guard let text = String(data: data, encoding: .utf8) else {
            throw ACPTransportError.unsupported("Could not encode message as UTF-8")
        }
        try await sendWithRetry(text)
    }

    public func receive() async throws -> JSONRPCMessage? {
        try ensureConnected()
        let incoming = try await receiveWithRetry()

        switch incoming {
        case .string(let text):
            return try framer.decodeLine(text)
        case .data(let data):
            return try JSONRPCCodec.decode(data)
        }
    }

    public func close() async {
        closed = true
        heartbeatTask?.cancel()
        heartbeatTask = nil
        if let connection {
            await connection.close()
        }
        connection = nil
    }
}

private extension WebSocketClientTransport {
    func reconnect(force: Bool) async throws {
        if force || connection == nil {
            heartbeatTask?.cancel()
            heartbeatTask = nil
            if let connection {
                await connection.close()
            }
            connection = nil
        }
        if connection != nil { return }

        connection = try await connectionFactory.make(endpoint: endpoint, headers: headers)
        startHeartbeatIfNeeded()
    }

    func sendWithRetry(_ text: String) async throws {
        var attempt = 0
        while true {
            do {
                guard let connection else { throw ACPTransportError.notConnected }
                try await connection.send(text: text)
                return
            } catch {
                guard !closed, options.retryPolicy.canRetry(attempt) else {
                    throw error
                }
                attempt += 1
                try await sleepBeforeRetry(attempt: attempt)
                try await reconnect(force: true)
            }
        }
    }

    func receiveWithRetry() async throws -> WebSocketIncomingMessage {
        var attempt = 0
        while true {
            do {
                guard let connection else { throw ACPTransportError.notConnected }
                return try await connection.receive()
            } catch {
                guard !closed, options.retryPolicy.canRetry(attempt) else {
                    throw error
                }
                attempt += 1
                try await sleepBeforeRetry(attempt: attempt)
                try await reconnect(force: true)
            }
        }
    }

    func sleepBeforeRetry(attempt: Int) async throws {
        let delay = options.retryPolicy.delayNanoseconds(for: attempt)
        if delay > 0 {
            try await Task.sleep(nanoseconds: delay)
        }
    }

    func startHeartbeatIfNeeded() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        guard let interval = options.heartbeatIntervalNanoseconds, interval > 0 else { return }

        heartbeatTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: interval)
                if Task.isCancelled { return }
                await self.sendPingIfNeeded()
            }
        }
    }

    func sendPingIfNeeded() async {
        guard !closed else { return }
        var attempt = 0
        while true {
            do {
                guard let connection else { throw ACPTransportError.notConnected }
                try await connection.sendPing()
                return
            } catch {
                guard !closed, options.retryPolicy.canRetry(attempt) else { return }
                attempt += 1
                try? await sleepBeforeRetry(attempt: attempt)
                try? await reconnect(force: true)
            }
        }
    }

    func ensureConnected() throws {
        if closed || connection == nil {
            throw ACPTransportError.notConnected
        }
    }
}

public struct URLSessionWebSocketConnectionFactory: WebSocketConnectionFactory {
    public init() {}

    public func make(endpoint: URL, headers: [String: String]) async throws -> any WebSocketConnection {
        URLSessionWebSocketConnection(endpoint: endpoint, headers: headers)
    }
}

public final class URLSessionWebSocketConnection: @unchecked Sendable, WebSocketConnection {
    private let session: URLSession
    private let task: URLSessionWebSocketTask

    public init(endpoint: URL, headers: [String: String]) {
        let session = URLSession(configuration: .default)
        var request = URLRequest(url: endpoint)
        for (k, v) in headers {
            request.setValue(v, forHTTPHeaderField: k)
        }
        let task = session.webSocketTask(with: request)
        task.resume()
        self.session = session
        self.task = task
    }

    public func send(text: String) async throws {
        try await task.send(.string(text))
    }

    public func receive() async throws -> WebSocketIncomingMessage {
        let incoming = try await task.receive()
        switch incoming {
        case .string(let text):
            return .string(text)
        case .data(let data):
            return .data(data)
        @unknown default:
            throw ACPTransportError.unsupported("Unknown websocket message")
        }
    }

    public func sendPing() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task.sendPing { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    public func close() async {
        task.cancel(with: .goingAway, reason: nil)
        session.invalidateAndCancel()
    }
}
