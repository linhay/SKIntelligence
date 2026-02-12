import Foundation
import SKIACP

public actor ACPBridgeBackedPermissionPolicy: ACPPermissionPolicy {
    public typealias Requester = @Sendable (ACPSessionPermissionRequestParams) async throws -> ACPSessionPermissionRequestResult

    private let mode: ACPPermissionPolicyMode
    private let allowOnBridgeError: Bool
    private let requester: Requester
    private let memoryStore: ACPPermissionMemoryStore

    public init(
        mode: ACPPermissionPolicyMode,
        allowOnBridgeError: Bool = false,
        memoryStore: ACPPermissionMemoryStore = .init(),
        requester: @escaping Requester
    ) {
        self.mode = mode
        self.allowOnBridgeError = allowOnBridgeError
        self.memoryStore = memoryStore
        self.requester = requester
    }

    public func evaluate(_ request: ACPSessionPermissionRequestParams) async throws -> ACPSessionPermissionRequestResult {
        let fingerprint = ACPToolCallFingerprint(request)
        if let outcome = await memoryStore.get(sessionId: request.sessionId, fingerprint: fingerprint) {
            if case .selected(let selected) = outcome, selected.optionId == "reject_always" {
                return .init(outcome: .cancelled)
            }
            return .init(outcome: outcome)
        }

        switch mode {
        case .allow:
            return .init(outcome: .selected(.init(optionId: "allow_once")))
        case .deny:
            return .init(outcome: .cancelled)
        case .ask:
            do {
                return try await requester(request)
            } catch {
                guard allowOnBridgeError else { throw error }
                return .init(outcome: .selected(.init(optionId: "allow_once")))
            }
        }
    }

    public func remember(_ request: ACPSessionPermissionRequestParams, decision: ACPSessionPermissionRequestResult) async {
        guard case .selected(let selected) = decision.outcome else { return }
        let option = selected.optionId
        guard option == "allow_always" || option == "reject_always" else { return }

        let fingerprint = ACPToolCallFingerprint(request)
        await memoryStore.set(
            sessionId: request.sessionId,
            fingerprint: fingerprint,
            outcome: .selected(.init(optionId: option))
        )
    }

    public func clear(sessionId: String) async {
        await memoryStore.clear(sessionId: sessionId)
    }
}
