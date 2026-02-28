import Foundation
import Network
import SKIACP
@preconcurrency import STJSON

public actor WebSocketServerTransport: ACPTransport {
    public struct Options: Sendable, Equatable {
        public var maxInFlightSends: Int

        public init(maxInFlightSends: Int = 64) {
            self.maxInFlightSends = max(1, maxInFlightSends)
        }
    }

    private struct ResponseRoute {
        let connectionID: ObjectIdentifier
        let originalID: JSONRPC.ID
        let method: String
    }

    private let listenAddress: String
    private let gate: ACPTransportBackpressureGate
    private let queue = DispatchQueue(label: "SKIACPTransport.WebSocketServerTransport")

    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var responseRoutes: [JSONRPC.ID: ResponseRoute] = [:]
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
            guard let originalID = request.id else {
                return .notification(request)
            }
            let internalID = JSONRPC.ID.string("s2c-\(nextInternalRequestID)")
            nextInternalRequestID += 1
            responseRoutes[internalID] = .init(connectionID: connectionID, originalID: originalID, method: request.method)
            let routed = JSONRPC.Request(id: internalID, method: request.method, params: request.paramsValue)
            return .request(routed)
        case .notification(let notification):
            return .notification(remapCancelRequestIfNeeded(notification, connectionID: connectionID))
        case .response:
            return message
        }
    }

    func remapCancelRequestIfNeeded(_ notification: JSONRPC.Request, connectionID: ObjectIdentifier) -> JSONRPC.Request {
        guard notification.method == "$/cancel_request",
              let paramsValue = notification.paramsValue,
              var object = try? paramsValue.decode(to: [String: AnyCodable].self),
              let requestIDValue = object["requestId"],
              let originalID = jsonRPCID(from: requestIDValue),
              let internalID = internalRequestID(for: originalID, connectionID: connectionID) else {
            return notification
        }
        object["requestId"] = jsonValue(from: internalID)
        return JSONRPC.Request(method: notification.method, params: AnyCodable(object))
    }

    func internalRequestID(for originalID: JSONRPC.ID, connectionID: ObjectIdentifier) -> JSONRPC.ID? {
        for (internalID, route) in responseRoutes where route.connectionID == connectionID && route.originalID == originalID {
            return internalID
        }
        return nil
    }

    func jsonRPCID(from value: AnyCodable) -> JSONRPC.ID? {
        if let number = numericDouble(from: value.value) {
            let rounded = number.rounded(.towardZero)
            guard rounded == number else { return nil }
            return .int(Int(rounded))
        }
        if let string = value.value as? String {
            return .string(string)
        }
        return nil
    }

    func jsonValue(from id: JSONRPC.ID) -> AnyCodable {
        switch id {
        case .int(let value):
            return AnyCodable(Double(value))
        case .string(let value):
            return AnyCodable(value)
        case .null:
            return AnyCodable(nil as String?)
        }
    }

    func routedTargets(for message: JSONRPCMessage) throws -> [(NWConnection, JSONRPCMessage)] {
        switch message {
        case .response(let response):
            guard let responseID = response.id else {
                throw ACPTransportError.notConnected
            }
            if let route = responseRoutes.removeValue(forKey: responseID),
               let connection = connections[route.connectionID] {
                if (route.method == "session/new" || route.method == "session/fork"),
                   let sessionID = extractSessionIDFromResult(response.result) {
                    sessionOwners[sessionID] = route.connectionID
                }
                let restored = JSONRPC.Response(id: route.originalID, result: response.result, error: response.error)
                return [(connection, .response(restored))]
            }
            throw ACPTransportError.notConnected
        case .notification:
            if case .notification(let notification) = message,
               let sessionID = extractSessionIDFromParams(notification.paramsValue),
               let ownerID = sessionOwners[sessionID],
               let connection = connections[ownerID] {
                return [(connection, message)]
            }
            return connections.values.map { ($0, message) }
        case .request:
            if case .request(let request) = message,
               let sessionID = extractSessionIDFromParams(request.paramsValue),
               let ownerID = sessionOwners[sessionID],
               let connection = connections[ownerID] {
                return [(connection, message)]
            }
            throw ACPTransportError.unsupported("Could not route request to client owner by sessionId")
        }
    }

    func removeConnection(_ connectionID: ObjectIdentifier) {
        connections.removeValue(forKey: connectionID)
        responseRoutes = responseRoutes.reduce(into: [:]) { partial, element in
            if element.value.connectionID != connectionID {
                partial[element.key] = element.value
            }
        }
        sessionOwners = sessionOwners.filter { $0.value != connectionID }
    }

    func extractSessionIDFromParams(_ params: AnyCodable?) -> String? {
        guard
            let params,
            let object = try? params.decode(to: [String: AnyCodable].self)
        else { return nil }
        return object["sessionId"]?.value as? String
    }

    func extractSessionIDFromResult(_ result: AnyCodable?) -> String? {
        guard
            let result,
            let object = try? result.decode(to: [String: AnyCodable].self)
        else { return nil }
        return object["sessionId"]?.value as? String
    }

    func numericDouble(from raw: Any) -> Double? {
        switch raw {
        case let value as Double: return value
        case let value as Float: return Double(value)
        case let value as Int: return Double(value)
        case let value as Int8: return Double(value)
        case let value as Int16: return Double(value)
        case let value as Int32: return Double(value)
        case let value as Int64: return Double(value)
        case let value as UInt: return Double(value)
        case let value as UInt8: return Double(value)
        case let value as UInt16: return Double(value)
        case let value as UInt32: return Double(value)
        case let value as UInt64: return Double(value)
        default: return nil
        }
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
