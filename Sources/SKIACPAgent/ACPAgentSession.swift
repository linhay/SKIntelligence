import SKIntelligence

public protocol ACPAgentSession: Sendable {
    func prompt(_ text: String) async throws -> String
    func snapshotEntries() async throws -> [SKITranscript.Entry]
    func restoreEntries(_ entries: [SKITranscript.Entry]) async throws
}

extension SKILanguageModelSession: ACPAgentSession {
    public func prompt(_ text: String) async throws -> String {
        try await respond(to: text)
    }

    public func snapshotEntries() async throws -> [SKITranscript.Entry] {
        await transcript.entries
    }

    public func restoreEntries(_ entries: [SKITranscript.Entry]) async throws {
        await transcript.replaceEntries(entries)
    }
}

extension SKIAgentSession: ACPAgentSession {
    public func snapshotEntries() async throws -> [SKITranscript.Entry] {
        await transcriptEntries()
    }

    public func restoreEntries(_ entries: [SKITranscript.Entry]) async throws {
        try await resume(with: entries)
    }
}
