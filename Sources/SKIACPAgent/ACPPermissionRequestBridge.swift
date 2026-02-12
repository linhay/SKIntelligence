import Foundation
import SKIACP
import SKIJSONRPC

public enum ACPPermissionRequestBridgeError: Error, LocalizedError, Equatable {
    case requestTimeout
    case rpcError(code: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .requestTimeout:
            return "Permission request timed out"
        case .rpcError(_, let message):
            return message
        }
    }
}

public actor ACPPermissionRequestBridge {
    public typealias RequestSender = @Sendable (JSONRPCRequest) async throws -> Void

    private let timeoutNanoseconds: UInt64?
    private var nextID: Int = 1
    private var pending: [JSONRPCID: CheckedContinuation<ACPSessionPermissionRequestResult, Error>] = [:]
    private var timeoutTasks: [JSONRPCID: Task<Void, Never>] = [:]

    public init(timeoutNanoseconds: UInt64? = 10_000_000_000) {
        self.timeoutNanoseconds = timeoutNanoseconds
    }

    public func requestPermission(
        _ params: ACPSessionPermissionRequestParams,
        send: @escaping RequestSender
    ) async throws -> ACPSessionPermissionRequestResult {
        let id = JSONRPCID.string("perm-\(nextID)")
        nextID += 1

        let request = JSONRPCRequest(
            id: id,
            method: ACPMethods.sessionRequestPermission,
            params: try ACPCodec.encodeParams(params)
        )

        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            if let timeoutNanoseconds {
                timeoutTasks[id] = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                    await self?.timeoutPending(id)
                }
            }
            Task {
                do {
                    try await send(request)
                } catch {
                    self.failPending(id, error: error)
                }
            }
        }
    }

    public func handleIncomingResponse(_ response: JSONRPCResponse) -> Bool {
        guard let continuation = pending.removeValue(forKey: response.id) else {
            return false
        }
        timeoutTasks[response.id]?.cancel()
        timeoutTasks[response.id] = nil

        if let rpcError = response.error {
            continuation.resume(throwing: ACPPermissionRequestBridgeError.rpcError(code: rpcError.code, message: rpcError.message))
            return true
        }

        do {
            let result = try ACPCodec.decodeResult(response.result, as: ACPSessionPermissionRequestResult.self)
            continuation.resume(returning: result)
        } catch {
            continuation.resume(throwing: error)
        }
        return true
    }

    public func failAll(_ error: Error) {
        let continuations = pending
        pending.removeAll()
        let tasks = timeoutTasks
        timeoutTasks.removeAll()
        tasks.values.forEach { $0.cancel() }
        continuations.values.forEach { $0.resume(throwing: error) }
    }
}

private extension ACPPermissionRequestBridge {
    func timeoutPending(_ id: JSONRPCID) {
        guard pending[id] != nil else { return }
        failPending(id, error: ACPPermissionRequestBridgeError.requestTimeout)
    }

    func failPending(_ id: JSONRPCID, error: Error) {
        timeoutTasks[id]?.cancel()
        timeoutTasks[id] = nil
        guard let continuation = pending.removeValue(forKey: id) else { return }
        continuation.resume(throwing: error)
    }
}
