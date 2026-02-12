import Foundation
import SKIACPTransport

public enum SKICLIValidationError: Error, LocalizedError, CustomNSError, Equatable {
    case invalidInput(String)

    public var errorDescription: String? {
        switch self {
        case .invalidInput(let message):
            return message
        }
    }

    public static var errorDomain: String {
        "SKICLIValidationError"
    }

    public var errorCode: Int {
        switch self {
        case .invalidInput:
            return 2
        }
    }

    public var errorUserInfo: [String: Any] {
        [NSLocalizedDescriptionKey: errorDescription ?? "Invalid input"]
    }
}

public enum SKICLITransportKind: String, Sendable {
    case stdio
    case ws
}

public enum ACPCLITransportFactory {
    public static func millisecondsToNanosecondsNonNegative(_ value: Int?) -> UInt64? {
        value.map { UInt64(max($0, 0)) * 1_000_000 }
    }

    public static func makeClientTransport(
        kind: SKICLITransportKind,
        cmd: String?,
        args: [String],
        endpoint: String?,
        wsHeartbeatMS: Int,
        wsReconnectAttempts: Int,
        wsReconnectBaseDelayMS: Int,
        maxInFlightSends: Int
    ) throws -> any ACPTransport {
        switch kind {
        case .stdio:
            guard let cmd else {
                throw SKICLIValidationError.invalidInput("--cmd is required for stdio transport")
            }
            return ProcessStdioTransport(executable: cmd, arguments: args)

        case .ws:
            guard let endpoint, let url = URL(string: endpoint) else {
                throw SKICLIValidationError.invalidInput("--endpoint is required for ws transport")
            }
            let heartbeatNanos: UInt64? = wsHeartbeatMS <= 0 ? nil : UInt64(wsHeartbeatMS) * 1_000_000
            return WebSocketClientTransport(
                endpoint: url,
                options: .init(
                    heartbeatIntervalNanoseconds: heartbeatNanos,
                    retryPolicy: .init(
                        maxAttempts: max(0, wsReconnectAttempts),
                        baseDelayNanoseconds: UInt64(max(1, wsReconnectBaseDelayMS)) * 1_000_000
                    ),
                    maxInFlightSends: maxInFlightSends
                )
            )
        }
    }

    public static func makeServerTransport(
        kind: SKICLITransportKind,
        listen: String,
        maxInFlightSends: Int
    ) throws -> any ACPTransport {
        switch kind {
        case .stdio:
            return StdioTransport()
        case .ws:
            guard isValidListenAddress(listen) else {
                throw SKICLIValidationError.invalidInput("--listen must be in host:port format with port in 1...65535")
            }
            return WebSocketServerTransport(
                listenAddress: listen,
                options: .init(maxInFlightSends: maxInFlightSends)
            )
        }
    }
}

private extension ACPCLITransportFactory {
    static func isValidListenAddress(_ listen: String) -> Bool {
        let raw = listen
            .replacingOccurrences(of: "ws://", with: "")
            .replacingOccurrences(of: "wss://", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separator = raw.lastIndex(of: ":") else { return false }
        let host = String(raw[..<separator])
        let portText = String(raw[raw.index(after: separator)...])
        guard !host.isEmpty, let port = Int(portText), (1...65535).contains(port) else {
            return false
        }
        return true
    }
}
