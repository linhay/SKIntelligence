import Foundation
import Network
import SKIJSONRPC

public actor WebSocketServerTransport: ACPTransport {
    public struct Options: Sendable, Equatable {
        public var maxInFlightSends: Int

        public init(maxInFlightSends: Int = 64) {
            self.maxInFlightSends = max(1, maxInFlightSends)
        }
    }

    private struct ResponseRoute {
        let connectionID: ObjectIdentifier
        let originalID: JSONRPCID
        let method: String
    }

    private let listenAddress: String
    private let gate: ACPTransportBackpressureGate
    private let queue = DispatchQueue(label: "SKIACPTransport.WebSocketServerTransport")

    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var responseRoutes: [JSONRPCID: ResponseRoute] = [:]
    private var sessionOwners: [String: ObjectIdentifier] = [:]
    private var nextInternalRequestID: UInt64 = 1
    private var startContinuation: CheckedContinuation<Void, Error>?
    private var pendingMessages: [JSONRPCMessage] = []
    private var receiveContinuations: [CheckedContinuation<JSONRPCMessage?, Error>] = []
    private var isClosed = false

    public init(listenAddress: String, options: Options = .init()) {
        self.listenAddress = listenAddress
        self.gate = ACPTransportBackpressureGate(maxInFlight: options.maxInFlightSends)
    }

    public func connect() async throws {
        if listener != nil { return }
        isClosed = false

        let endpoint = try Self.parseListenAddress(listenAddress)
        let tcp = NWProtocolTCP.Options()
        let ws = NWProtocolWebSocket.Options()
        ws.autoReplyPing = true

        let params = NWParameters(tls: nil, tcp: tcp)
        params.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
        params.requiredLocalEndpoint = .hostPort(host: endpoint.host, port: endpoint.port)

        let listener = try NWListener(using: params)
        self.listener = listener

        listener.stateUpdateHandler = { [weak self] state in
            Task { await self?.onListenerState(state) }
        }
        listener.newConnectionHandler = { [weak self] connection in
            Task { await self?.onNewConnection(connection) }
        }

        try await withCheckedThrowingContinuation { continuation in
            startContinuation = continuation
            listener.start(queue: queue)
        }
    }

    public func send(_ message: JSONRPCMessage) async throws {
        guard !isClosed else { throw ACPTransportError.notConnected }

        let targets = try routedTargets(for: message)
        guard !targets.isEmpty else { throw ACPTransportError.notConnected }

        for (connection, routedMessage) in targets {
            await gate.acquire()
            defer { Task { await gate.release() } }
            let data = try JSONRPCCodec.encode(routedMessage)
            try await send(data: data, to: connection)
        }
    }

    public func receive() async throws -> JSONRPCMessage? {
        if !pendingMessages.isEmpty {
            return pendingMessages.removeFirst()
        }
        if isClosed {
            return nil
        }

        return try await withCheckedThrowingContinuation { continuation in
            receiveContinuations.append(continuation)
        }
    }

    public func close() async {
        isClosed = true
        listener?.cancel()
        listener = nil

        let activeConnections = Array(connections.values)
        connections.removeAll()
        responseRoutes.removeAll()
        sessionOwners.removeAll()
        activeConnections.forEach { $0.cancel() }

        pendingMessages.removeAll()

        if let startContinuation {
            self.startContinuation = nil
            startContinuation.resume(throwing: ACPTransportError.eof)
        }
        let continuations = receiveContinuations
        receiveContinuations.removeAll()
        continuations.forEach { $0.resume(returning: nil) }
    }
}

private extension WebSocketServerTransport {
    struct ListenEndpoint {
        let host: NWEndpoint.Host
        let port: NWEndpoint.Port
    }

    static func parseListenAddress(_ value: String) throws -> ListenEndpoint {
        let raw = value
            .replacingOccurrences(of: "ws://", with: "")
            .replacingOccurrences(of: "wss://", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separator = raw.lastIndex(of: ":") else {
            throw ACPTransportError.unsupported("Invalid listen address: \(value)")
        }

        let hostText = String(raw[..<separator])
        let portText = String(raw[raw.index(after: separator)...])
        guard !hostText.isEmpty,
              let portValue = UInt16(portText),
              let port = NWEndpoint.Port(rawValue: portValue) else {
            throw ACPTransportError.unsupported("Invalid listen address: \(value)")
        }

        return ListenEndpoint(host: .init(hostText), port: port)
    }

    func onListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            if let startContinuation {
                self.startContinuation = nil
                startContinuation.resume()
            }
        case .failed(let error):
            if let startContinuation {
                self.startContinuation = nil
                startContinuation.resume(throwing: error)
            }
        case .cancelled:
            if let startContinuation {
                self.startContinuation = nil
                startContinuation.resume(throwing: ACPTransportError.eof)
            }
        default:
            break
        }
    }

    func onNewConnection(_ newConnection: NWConnection) {
        let connectionID = ObjectIdentifier(newConnection)
        connections[connectionID] = newConnection

        newConnection.stateUpdateHandler = { [weak self] state in
            Task { await self?.onConnectionState(state, connection: newConnection) }
        }

        newConnection.start(queue: queue)
        scheduleReceive(on: newConnection)
    }

    func onConnectionState(_ state: NWConnection.State, connection: NWConnection) {
        let connectionID = ObjectIdentifier(connection)
        switch state {
        case .failed, .cancelled:
            removeConnection(connectionID)
        default:
            break
        }
    }

    func scheduleReceive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, context, _, error in
            Task {
                await self?.onReceive(data: data, context: context, error: error, connection: connection)
            }
        }
    }

    func onReceive(
        data: Data?,
        context: NWConnection.ContentContext?,
        error: NWError?,
        connection: NWConnection
    ) {
        let connectionID = ObjectIdentifier(connection)

        if let error {
            removeConnection(connectionID)
            if case .posix(let code) = error, code == .ECANCELED {
                return
            }
            return
        }

        guard connections[connectionID] != nil else { return }

        if let data, !data.isEmpty {
            do {
                let decoded = try decodeMessage(data: data, context: context)
                let inbound = routeInboundMessage(decoded, from: connectionID)
                if let continuation = receiveContinuations.first {
                    receiveContinuations.removeFirst()
                    continuation.resume(returning: inbound)
                } else {
                    pendingMessages.append(inbound)
                }
            } catch {
                if let continuation = receiveContinuations.first {
                    receiveContinuations.removeFirst()
                    continuation.resume(throwing: error)
                }
            }
        }

        guard !isClosed, connections[connectionID] != nil else { return }
        scheduleReceive(on: connection)
    }

    func decodeMessage(data: Data, context: NWConnection.ContentContext?) throws -> JSONRPCMessage {
        if let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata {
            switch metadata.opcode {
            case .binary:
                return try JSONRPCCodec.decode(data)
            case .text:
                guard let text = String(data: data, encoding: .utf8) else {
                    throw ACPTransportError.unsupported("WebSocket text frame is not UTF-8")
                }
                return try JSONRPCLineFramer().decodeLine(text)
            default:
                throw ACPTransportError.unsupported("Unsupported websocket frame opcode")
            }
        }
        return try JSONRPCCodec.decode(data)
    }

    func routeInboundMessage(_ message: JSONRPCMessage, from connectionID: ObjectIdentifier) -> JSONRPCMessage {
        switch message {
        case .request(let request):
            let internalID = JSONRPCID.string("s2c-\(nextInternalRequestID)")
            nextInternalRequestID += 1
            responseRoutes[internalID] = .init(connectionID: connectionID, originalID: request.id, method: request.method)
            let routed = JSONRPCRequest(id: internalID, method: request.method, params: request.params)
            return .request(routed)
        case .notification(let notification):
            return .notification(remapCancelRequestIfNeeded(notification, connectionID: connectionID))
        case .response:
            return message
        }
    }

    func remapCancelRequestIfNeeded(_ notification: JSONRPCNotification, connectionID: ObjectIdentifier) -> JSONRPCNotification {
        guard notification.method == "$/cancel_request",
              let params = notification.params,
              case .object(var object) = params,
              let requestIDValue = object["requestId"],
              let originalID = jsonRPCID(from: requestIDValue),
              let internalID = internalRequestID(for: originalID, connectionID: connectionID) else {
            return notification
        }
        object["requestId"] = jsonValue(from: internalID)
        return JSONRPCNotification(method: notification.method, params: .object(object))
    }

    func internalRequestID(for originalID: JSONRPCID, connectionID: ObjectIdentifier) -> JSONRPCID? {
        for (internalID, route) in responseRoutes where route.connectionID == connectionID && route.originalID == originalID {
            return internalID
        }
        return nil
    }

    func jsonRPCID(from value: JSONValue) -> JSONRPCID? {
        switch value {
        case .number(let number):
            let rounded = number.rounded(.towardZero)
            guard rounded == number else { return nil }
            return .int(Int(rounded))
        case .string(let string):
            return .string(string)
        default:
            return nil
        }
    }

    func jsonValue(from id: JSONRPCID) -> JSONValue {
        switch id {
        case .int(let value):
            return .number(Double(value))
        case .string(let value):
            return .string(value)
        }
    }

    func routedTargets(for message: JSONRPCMessage) throws -> [(NWConnection, JSONRPCMessage)] {
        switch message {
        case .response(let response):
            if let route = responseRoutes.removeValue(forKey: response.id),
               let connection = connections[route.connectionID] {
                if (route.method == "session/new" || route.method == "session/fork"),
                   let sessionID = extractSessionIDFromResult(response.result) {
                    sessionOwners[sessionID] = route.connectionID
                }
                let restored = JSONRPCResponse(id: route.originalID, result: response.result, error: response.error)
                return [(connection, .response(restored))]
            }
            throw ACPTransportError.notConnected
        case .notification:
            if case .notification(let notification) = message,
               let sessionID = extractSessionIDFromParams(notification.params),
               let ownerID = sessionOwners[sessionID],
               let connection = connections[ownerID] {
                return [(connection, message)]
            }
            return connections.values.map { ($0, message) }
        case .request:
            if case .request(let request) = message,
               let sessionID = extractSessionIDFromParams(request.params),
               let ownerID = sessionOwners[sessionID],
               let connection = connections[ownerID] {
                return [(connection, message)]
            }
            throw ACPTransportError.unsupported("Could not route request to client owner by sessionId")
        }
    }

    func removeConnection(_ connectionID: ObjectIdentifier) {
        connections.removeValue(forKey: connectionID)
        responseRoutes = responseRoutes.filter { $0.value.connectionID != connectionID }
        sessionOwners = sessionOwners.filter { $0.value != connectionID }
    }

    func extractSessionIDFromParams(_ params: JSONValue?) -> String? {
        guard let params, case .object(let object) = params, case .string(let sessionID)? = object["sessionId"] else {
            return nil
        }
        return sessionID
    }

    func extractSessionIDFromResult(_ result: JSONValue?) -> String? {
        guard let result, case .object(let object) = result, case .string(let sessionID)? = object["sessionId"] else {
            return nil
        }
        return sessionID
    }

    func send(data: Data, to connection: NWConnection) async throws {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
        let context = NWConnection.ContentContext(identifier: "jsonrpc", metadata: [metadata])

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }
}
