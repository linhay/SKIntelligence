import XCTest

@testable import SKIntelligence

final class SKIMemoryTests: XCTestCase {

    // MARK: - SKIMemoryMessage Tests

    func testMemoryMessageCreation() {
        let userMsg = SKIMemoryMessage.user("Hello")
        XCTAssertEqual(userMsg.role, .user)
        XCTAssertEqual(userMsg.content, "Hello")

        let assistantMsg = SKIMemoryMessage.assistant("Hi there!")
        XCTAssertEqual(assistantMsg.role, .assistant)

        let systemMsg = SKIMemoryMessage.system("You are helpful")
        XCTAssertEqual(systemMsg.role, .system)

        let toolMsg = SKIMemoryMessage.tool("Result", toolName: "search")
        XCTAssertEqual(toolMsg.role, .tool)
        XCTAssertEqual(toolMsg.metadata["tool_name"], "search")
    }

    func testMemoryMessageChatConversion() {
        let memoryMsg = SKIMemoryMessage.user("Test message")
        let chatMsg = memoryMsg.toChatMessage()

        if case .user(let content, _) = chatMsg {
            if case .text(let text) = content {
                XCTAssertEqual(text, "Test message")
            } else {
                XCTFail("Expected text content")
            }
        } else {
            XCTFail("Expected user message")
        }
    }

    func testMemoryMessageFromChatMessage() {
        let chatMsg = ChatRequestBody.Message.user(content: .text("From chat"))
        let memoryMsg = SKIMemoryMessage(from: chatMsg)

        XCTAssertNotNil(memoryMsg)
        XCTAssertEqual(memoryMsg?.role, .user)
        XCTAssertEqual(memoryMsg?.content, "From chat")
    }

    // MARK: - SKIConversationMemory Tests

    func testConversationMemoryBasic() async {
        let memory = SKIConversationMemory(maxMessages: 5)

        let isEmptyBefore = await memory.isEmpty
        XCTAssertTrue(isEmptyBefore)

        let countBefore = await memory.count
        XCTAssertEqual(countBefore, 0)

        await memory.add(.user("Hello"))
        await memory.add(.assistant("Hi!"))

        let countAfter = await memory.count
        XCTAssertEqual(countAfter, 2)

        let isEmptyAfter = await memory.isEmpty
        XCTAssertFalse(isEmptyAfter)

        let messages = await memory.allMessages()
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].content, "Hello")
        XCTAssertEqual(messages[1].content, "Hi!")
    }

    func testConversationMemoryLimit() async {
        let memory = SKIConversationMemory(maxMessages: 3)

        await memory.add(.user("Message 1"))
        await memory.add(.user("Message 2"))
        await memory.add(.user("Message 3"))
        await memory.add(.user("Message 4"))
        await memory.add(.user("Message 5"))

        let count = await memory.count
        XCTAssertEqual(count, 3)

        let messages = await memory.allMessages()
        XCTAssertEqual(messages[0].content, "Message 3")
        XCTAssertEqual(messages[1].content, "Message 4")
        XCTAssertEqual(messages[2].content, "Message 5")
    }

    func testConversationMemoryContext() async {
        let memory = SKIConversationMemory(maxMessages: 10)

        await memory.add(.user("First"))
        await memory.add(.assistant("Second"))
        await memory.add(.user("Third"))
        await memory.add(.assistant("Fourth"))

        // Get limited context
        let limited = await memory.context(for: "", maxMessages: 2)
        XCTAssertEqual(limited.count, 2)
        XCTAssertEqual(limited[0].content, "Third")
        XCTAssertEqual(limited[1].content, "Fourth")

        // Get all context
        let all = await memory.context(for: "", maxMessages: nil)
        XCTAssertEqual(all.count, 4)
    }

    func testConversationMemoryClear() async {
        let memory = SKIConversationMemory(maxMessages: 10)

        await memory.add(.user("Message"))

        let countBefore = await memory.count
        XCTAssertEqual(countBefore, 1)

        await memory.clear()

        let countAfter = await memory.count
        XCTAssertEqual(countAfter, 0)

        let isEmpty = await memory.isEmpty
        XCTAssertTrue(isEmpty)
    }

    func testConversationMemoryBatchAdd() async {
        let memory = SKIConversationMemory(maxMessages: 10)

        await memory.addAll([
            .user("One"),
            .assistant("Two"),
            .user("Three"),
        ])

        let count = await memory.count
        XCTAssertEqual(count, 3)
    }

    func testConversationMemoryFilter() async {
        let memory = SKIConversationMemory(maxMessages: 10)

        await memory.add(.user("User message"))
        await memory.add(.assistant("Assistant message"))
        await memory.add(.user("Another user message"))

        let userMessages = await memory.messages(withRole: .user)
        XCTAssertEqual(userMessages.count, 2)

        let assistantMessages = await memory.messages(withRole: .assistant)
        XCTAssertEqual(assistantMessages.count, 1)
    }

    // MARK: - SKISummaryMemory Tests

    func testSummaryMemoryBasic() async {
        let memory = SKISummaryMemory(
            configuration: .init(
                recentMessageCount: 3,
                summarizationThreshold: 5,
                summaryMaxLength: 500
            )
        )

        await memory.add(.user("Hello"))
        await memory.add(.assistant("Hi!"))

        let count = await memory.count
        XCTAssertEqual(count, 2)

        let hasSummary = await memory.hasSummary
        XCTAssertFalse(hasSummary)
    }

    func testSummaryMemorySummarization() async {
        // Configuration enforces: recentMessageCount >= 5, threshold >= recentMessageCount + 10
        // So with recentMessageCount: 5, threshold becomes at least 15
        let memory = SKISummaryMemory(
            configuration: .init(
                recentMessageCount: 5,
                summarizationThreshold: 15,
                summaryMaxLength: 500
            )
        )

        // Add 15 messages to trigger summarization
        for i in 1...15 {
            await memory.add(.user("Message \(i)"))
        }

        // Summarization should have occurred
        let hasSummary = await memory.hasSummary
        XCTAssertTrue(hasSummary)

        let count = await memory.count
        XCTAssertEqual(count, 5)  // Only recentMessageCount messages remain

        let summary = await memory.currentSummary
        XCTAssertFalse(summary.isEmpty)
    }

    func testSummaryMemoryForceSummarize() async {
        // Configuration enforces: recentMessageCount >= 5, threshold >= recentMessageCount + 10
        let memory = SKISummaryMemory(
            configuration: .init(
                recentMessageCount: 5,
                summarizationThreshold: 100  // High threshold so auto-summarize doesn't trigger
            )
        )

        // Add more than recentMessageCount messages
        for i in 1...10 {
            await memory.add(.user("Message \(i)"))
        }

        let hasSummaryBefore = await memory.hasSummary
        XCTAssertFalse(hasSummaryBefore)

        await memory.forceSummarize()

        let hasSummaryAfter = await memory.hasSummary
        XCTAssertTrue(hasSummaryAfter)

        let count = await memory.count
        XCTAssertEqual(count, 5)  // Only recentMessageCount messages remain
    }

    func testSummaryMemorySetSummary() async {
        let memory = SKISummaryMemory()

        await memory.setSummary("Custom summary text")

        let hasSummary = await memory.hasSummary
        XCTAssertTrue(hasSummary)

        let currentSummary = await memory.currentSummary
        XCTAssertEqual(currentSummary, "Custom summary text")
    }

    // MARK: - SKISummarizer Tests

    func testTruncatingSummarizer() async throws {
        let summarizer = SKITruncatingSummarizer()

        let isAvailable = await summarizer.isAvailable
        XCTAssertTrue(isAvailable)

        let shortText = "Hello"
        let shortResult = try await summarizer.summarize(shortText, maxLength: 100)
        XCTAssertEqual(shortResult, "Hello")

        let longText = "This is a very long text that should be truncated"
        let truncated = try await summarizer.summarize(longText, maxLength: 20)
        XCTAssertTrue(truncated.count <= 20)
        XCTAssertTrue(truncated.hasSuffix("..."))
    }

    // MARK: - SKIInMemoryStore Tests

    func testInMemoryStoreBasic() async throws {
        let store = SKIInMemoryStore(storeId: "test-store")

        XCTAssertEqual(store.storeId, "test-store")

        let isEmptyBefore = await store.isEmpty
        XCTAssertTrue(isEmptyBefore)

        try await store.addItem(.user("Hello"))

        let count = await store.itemCount
        XCTAssertEqual(count, 1)

        let isEmptyAfter = await store.isEmpty
        XCTAssertFalse(isEmptyAfter)
    }

    func testInMemoryStoreGetItems() async throws {
        let store = SKIInMemoryStore()

        try await store.addItems([
            .user("One"),
            .assistant("Two"),
            .user("Three"),
        ])

        let all = try await store.getAllItems()
        XCTAssertEqual(all.count, 3)

        let limited = try await store.getItems(limit: 2)
        XCTAssertEqual(limited.count, 2)
        XCTAssertEqual(limited[0].content, "Two")
        XCTAssertEqual(limited[1].content, "Three")
    }

    func testInMemoryStorePopItem() async throws {
        let store = SKIInMemoryStore()

        try await store.addItems([
            .user("First"),
            .user("Second"),
        ])

        let popped = try await store.popItem()
        XCTAssertEqual(popped?.content, "Second")

        let countAfterPop = await store.itemCount
        XCTAssertEqual(countAfterPop, 1)

        let remaining = try await store.getAllItems()
        XCTAssertEqual(remaining[0].content, "First")
    }

    func testInMemoryStoreClear() async throws {
        let store = SKIInMemoryStore()

        try await store.addItem(.user("Test"))

        let countBefore = await store.itemCount
        XCTAssertEqual(countBefore, 1)

        try await store.clearStore()

        let countAfter = await store.itemCount
        XCTAssertEqual(countAfter, 0)

        let isEmpty = await store.isEmpty
        XCTAssertTrue(isEmpty)
    }

    // MARK: - SKIAnyMemory Type Erasure Tests

    func testAnyMemoryWrapper() async {
        let conversation = SKIConversationMemory(maxMessages: 10)
        let anyMemory = SKIAnyMemory(conversation)

        await anyMemory.add(.user("Test"))

        let count = await anyMemory.count
        XCTAssertEqual(count, 1)

        let messages = await anyMemory.allMessages()
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].content, "Test")
    }
}
