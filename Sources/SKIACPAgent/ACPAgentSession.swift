import SKIntelligence

public protocol ACPAgentSession: Sendable {
    func prompt(_ text: String) async throws -> String
}

extension SKILanguageModelSession: ACPAgentSession {
    public func prompt(_ text: String) async throws -> String {
        try await respond(to: text)
    }
}

extension SKIAgentSession: ACPAgentSession {}
