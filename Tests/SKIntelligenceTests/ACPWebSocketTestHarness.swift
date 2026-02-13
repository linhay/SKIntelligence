import Foundation
import XCTest
@testable import SKIACPTransport

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum ACPWebSocketTestHarness {
    static func makeServerTransport(
        host: String = "127.0.0.1",
        preferredPort: UInt16? = nil,
        attempts: Int = 24,
        portRange: ClosedRange<UInt16> = 22000...62000
    ) async throws -> (transport: WebSocketServerTransport, port: UInt16) {
        precondition(attempts > 0, "attempts must be > 0")

        var candidates: [UInt16] = []
        if let preferredPort {
            candidates.append(preferredPort)
        }
        while candidates.count < attempts {
            candidates.append(UInt16.random(in: portRange))
        }

        var lastAddressInUse: Error?
        for port in candidates {
            let transport = WebSocketServerTransport(listenAddress: "\(host):\(port)")
            do {
                try await transport.connect()
                return (transport, port)
            } catch {
                await transport.close()
                if isAddressInUse(error) {
                    lastAddressInUse = error
                    continue
                }
                throw error
            }
        }

        throw XCTSkip("Unable to allocate websocket port after \(attempts) attempts: \(lastAddressInUse?.localizedDescription ?? "unknown error")")
    }

    static func makeServerTransport(
        onFixedPort port: UInt16,
        host: String = "127.0.0.1",
        attempts: Int = 20,
        retryDelayNanoseconds: UInt64 = 60_000_000
    ) async throws -> WebSocketServerTransport {
        precondition(attempts > 0, "attempts must be > 0")

        var lastAddressInUse: Error?
        for index in 0..<attempts {
            let transport = WebSocketServerTransport(listenAddress: "\(host):\(port)")
            do {
                try await transport.connect()
                return transport
            } catch {
                await transport.close()
                if isAddressInUse(error) {
                    lastAddressInUse = error
                    if index < attempts - 1 {
                        try await Task.sleep(nanoseconds: retryDelayNanoseconds)
                    }
                    continue
                }
                throw error
            }
        }

        throw XCTSkip("Port \(port) still in use after \(attempts) retries: \(lastAddressInUse?.localizedDescription ?? "unknown error")")
    }

    static func isAddressInUse(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSPOSIXErrorDomain, ns.code == Int(EADDRINUSE) {
            return true
        }
        let description = (ns.userInfo[NSLocalizedDescriptionKey] as? String) ?? ns.localizedDescription
        return description.localizedCaseInsensitiveContains("address already in use")
    }
}
