import XCTest
@testable import SKIntelligence

final class SKITranscriptEventContractTests: XCTestCase {
    func testMessageEntryMapsToMessageEvent() async throws {
        let entry: SKITranscript.Entry = .message(.user(content: .text("hello")))
        let events = SKITranscript.events(from: entry)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].kind, .message)
        XCTAssertEqual(events[0].role, "user")
        XCTAssertEqual(events[0].content, "hello")
    }

    func testToolCallEntryMapsToToolCallAndExecutionStarted() async throws {
        let call = ChatRequestBody.Message.ToolCall(
            id: "call_1",
            function: .init(name: "read_file", arguments: "{\"path\":\"/tmp/a\"}")
        )
        let events = SKITranscript.events(from: .toolCalls(call))

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].kind, .toolCall)
        XCTAssertEqual(events[0].toolName, "read_file")
        XCTAssertEqual(events[0].toolCallId, "call_1")
        XCTAssertEqual(events[1].kind, .toolExecutionUpdate)
        XCTAssertEqual(events[1].state, .started)
    }

    func testToolOutputEntryMapsToToolResultAndExecutionCompleted() async throws {
        let call = ChatRequestBody.Message.ToolCall(
            id: "call_2",
            function: .init(name: "read_file", arguments: "{\"path\":\"/tmp/a\"}")
        )
        let output = SKITranscript.ToolOutput(content: .text("file-content"), toolCall: call)
        let events = SKITranscript.events(from: .toolOutput(output))

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].kind, .toolResult)
        XCTAssertEqual(events[0].content, "file-content")
        XCTAssertEqual(events[1].kind, .toolExecutionUpdate)
        XCTAssertEqual(events[1].state, .completed)
    }

    func testSessionUpdateEventFactory() async throws {
        let event = SKITranscript.sessionUpdateEvent(name: "current_mode_update", content: "default")
        XCTAssertEqual(event.kind, .sessionUpdate)
        XCTAssertEqual(event.sessionUpdateName, "current_mode_update")
        XCTAssertEqual(event.content, "default")
        XCTAssertEqual(event.source, .session)
    }

    func testTranscriptAggregatesEventSequence() async throws {
        let transcript = SKITranscript()
        try await transcript.append(prompt: .user(content: .text("q1")))

        let call = ChatRequestBody.Message.ToolCall(
            id: "call_3",
            function: .init(name: "list_dir", arguments: "{\"path\":\".\"}")
        )
        try await transcript.append(toolCalls: call)
        try await transcript.append(
            toolOutput: .init(content: .text("ok"), toolCall: call)
        )

        let events = await transcript.events()
        let kinds = events.map(\.kind)
        XCTAssertEqual(kinds, [.message, .toolCall, .toolExecutionUpdate, .toolResult, .toolExecutionUpdate])
        XCTAssertEqual(events[0].entryIndex, 0)
        XCTAssertEqual(events[1].entryIndex, 1)
        XCTAssertEqual(events[2].entryIndex, 1)
        XCTAssertEqual(events[3].entryIndex, 2)
        XCTAssertEqual(events[4].entryIndex, 2)
        XCTAssertTrue(events.allSatisfy { $0.source == .transcript })
    }

    func testEventsFromEntryWithIndexAnnotatesAllProducedEvents() async throws {
        let call = ChatRequestBody.Message.ToolCall(
            id: "call_9",
            function: .init(name: "run", arguments: "{\"cmd\":\"pwd\"}")
        )
        let events = SKITranscript.events(from: .toolCalls(call), entryIndex: 7)
        XCTAssertEqual(events.count, 2)
        XCTAssertTrue(events.allSatisfy { $0.entryIndex == 7 })
        XCTAssertTrue(events.allSatisfy { $0.source == .transcript })
    }
}
