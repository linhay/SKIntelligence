import Foundation
import SKIACP

/// Non-ACP extension point for local permission decision orchestration.
/// ACP payload uses `session/request_permission`; policy implementations must not
/// introduce extra protocol fields.
public protocol ACPPermissionPolicy: Sendable {
    func evaluate(_ request: ACPSessionPermissionRequestParams) async throws -> ACPSessionPermissionRequestResult
    func remember(_ request: ACPSessionPermissionRequestParams, decision: ACPSessionPermissionRequestResult) async
    func clear(sessionId: String) async
}
