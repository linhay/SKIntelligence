import XCTest
import HTTPTypes
@testable import SKIntelligence

final class SKIAgentSessionTests: XCTestCase {

    func testPromptAppendsTranscriptEntries() async throws {
        let session = SKIAgentSession(client: AgentEchoClient())

        let output = try await session.prompt("hello agent")
        XCTAssertTrue(output.contains("hello agent"))

        let entries = await session.transcriptEntries()
        XCTAssertGreaterThanOrEqual(entries.count, 2)
    }

    func testForkCopiesTranscriptAndKeepsIsolation() async throws {
        let session = SKIAgentSession(client: AgentEchoClient())
        _ = try await session.prompt("origin")

        let baseEntries = await session.transcriptEntries()
        let baseCount = baseEntries.count
        let forked = try await session.fork()
        let sessionID = await session.sessionId()
        let forkedID = await forked.sessionId()
        let forkedInitialEntries = await forked.transcriptEntries()
        let forkedInitialCount = forkedInitialEntries.count

        XCTAssertNotEqual(sessionID, forkedID)
        XCTAssertEqual(baseCount, forkedInitialCount)

        _ = try await forked.prompt("fork only")
        let originAfterForkEntries = await session.transcriptEntries()
        let forkedAfterPromptEntries = await forked.transcriptEntries()
        let originAfterForkCount = originAfterForkEntries.count
        let forkedAfterPromptCount = forkedAfterPromptEntries.count
        XCTAssertEqual(baseCount, originAfterForkCount)
        XCTAssertGreaterThan(forkedAfterPromptCount, baseCount)
    }

    func testResumeReplacesTranscriptEntries() async throws {
        let origin = SKIAgentSession(client: AgentEchoClient())
        _ = try await origin.prompt("to be resumed")
        let snapshot = await origin.transcriptEntries()

        let target = SKIAgentSession(client: AgentEchoClient())
        try await target.resume(with: snapshot)
        let resumedEntries = await target.transcriptEntries()

        XCTAssertEqual(snapshot.count, resumedEntries.count)
    }

    func testCancelActivePrompt() async throws {
        let session = SKIAgentSession(client: AgentSlowClient())

        let task: Task<String, Error> = Task { try await session.prompt("cancel me") }
        try await Task.sleep(nanoseconds: 50_000_000)
        await session.cancelActivePrompt()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation error")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }
}

private struct AgentEchoClient: SKILanguageModelClient {
    func respond(_ body: ChatRequestBody) async throws -> sending SKIResponse<ChatResponseBody> {
        let userText = body.messages.compactMap { message -> String? in
            if case .user(let content, _) = message, case .text(let text) = content {
                return text
            }
            return nil
        }.last ?? ""

        let payload = """
        {
          "choices": [
            {
              "finish_reason": "stop",
              "message": {
                "content": "ok: \(userText)",
                "role": "assistant"
              }
            }
          ],
          "created": 0,
          "model": "test"
        }
        """

        return try SKIResponse<ChatResponseBody>(
            httpResponse: .init(status: .ok),
            data: Data(payload.utf8)
        )
    }
}

private struct AgentSlowClient: SKILanguageModelClient {
    func respond(_ body: ChatRequestBody) async throws -> sending SKIResponse<ChatResponseBody> {
        _ = body
        try await Task.sleep(nanoseconds: 400_000_000)
        try Task.checkCancellation()

        let payload = """
        {
          "choices": [
            {
              "finish_reason": "stop",
              "message": {
                "content": "slow",
                "role": "assistant"
              }
            }
          ],
          "created": 0,
          "model": "test"
        }
        """

        return try SKIResponse<ChatResponseBody>(
            httpResponse: .init(status: .ok),
            data: Data(payload.utf8)
        )
    }
}
