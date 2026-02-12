import Foundation
import SKIACP

public protocol ACPPermissionPolicy: Sendable {
    func evaluate(_ request: ACPSessionPermissionRequestParams) async throws -> ACPSessionPermissionRequestResult
    func remember(_ request: ACPSessionPermissionRequestParams, decision: ACPSessionPermissionRequestResult) async
    func clear(sessionId: String) async
}
