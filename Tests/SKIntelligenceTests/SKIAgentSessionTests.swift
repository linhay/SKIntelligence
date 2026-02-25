import XCTest
import HTTPTypes
import JSONSchemaBuilder
import MCP
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

    func testForkDoesNotCopyQueuedPendingState() async throws {
        let session = SKIAgentSession(client: AgentDelayEchoClient(delayNanos: 220_000_000))
        let firstTask = Task { try await session.prompt("origin") }
        try await Task.sleep(nanoseconds: 20_000_000)

        await session.followUp("queued-parent-only")
        try await waitForPendingCount(expected: 1, in: session, timeoutNanos: 300_000_000)

        let forked = try await session.fork()
        let forkPending = await forked.pendingMessages(includeResolved: true)
        let forkPendingCount = await forked.pendingMessageCount()
        XCTAssertEqual(forkPending.count, 0)
        XCTAssertEqual(forkPendingCount, 0)

        _ = try await firstTask.value
    }

    func testForkDoesNotCopyResolvedPendingHistory() async throws {
        let session = SKIAgentSession(client: AgentDelayEchoClient(delayNanos: 80_000_000))
        await session.followUp("resolved-parent-only")
        try await Task.sleep(nanoseconds: 140_000_000)

        let parentHistory = await session.pendingMessages(includeResolved: true)
        XCTAssertTrue(parentHistory.contains(where: {
            $0.source == .followUp && $0.status == .resolved && $0.textPreview == "resolved-parent-only"
        }))

        let forked = try await session.fork()
        let forkHistory = await forked.pendingMessages(includeResolved: true)
        XCTAssertEqual(forkHistory.count, 0)
    }

    func testForkToolRegistryIsolationParentUnregisterDoesNotAffectChild() async throws {
        let session = SKIAgentSession(
            client: AgentEchoClient(),
            tools: [SessionEnabledTool(), SessionDisabledTool()]
        )
        let forked = try await session.fork()

        await session.unregister(toolNamed: "session_enabled_tool")

        let parentActive = await session.activeToolNames()
        let childActive = await forked.activeToolNames()
        XCTAssertEqual(parentActive, [])
        XCTAssertEqual(childActive, ["session_enabled_tool"])
    }

    func testForkToolRegistryIsolationChildUnregisterDoesNotAffectParent() async throws {
        let session = SKIAgentSession(
            client: AgentEchoClient(),
            tools: [SessionEnabledTool(), SessionDisabledTool()]
        )
        let forked = try await session.fork()

        await forked.unregister(toolNamed: "session_enabled_tool")

        let parentActive = await session.activeToolNames()
        let childActive = await forked.activeToolNames()
        XCTAssertEqual(parentActive, ["session_enabled_tool"])
        XCTAssertEqual(childActive, [])
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

    func testEnableJSONLPersistenceRestoresTranscriptAcrossSessions() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ski-agent-session-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let source = SKIAgentSession(client: AgentEchoClient())
        try await source.enableJSONLPersistence(fileURL: fileURL)
        _ = try await source.prompt("persist me")
        let sourceCount = await source.transcriptEntries().count
        XCTAssertGreaterThan(sourceCount, 0)

        let restored = SKIAgentSession(client: AgentEchoClient())
        try await restored.enableJSONLPersistence(fileURL: fileURL)
        let restoredEntries = await restored.transcriptEntries()
        XCTAssertEqual(restoredEntries.count, sourceCount)
    }

    func testForkableUserMessagesReturnsPromptHistoryInOrder() async throws {
        let session = SKIAgentSession(client: AgentEchoClient())
        _ = try await session.prompt("one")
        _ = try await session.prompt("two")
        _ = try await session.prompt("three")

        let messages = await session.forkableUserMessages()
        XCTAssertEqual(messages.map(\.text), ["one", "two", "three"])
        XCTAssertEqual(messages.count, 3)
    }

    func testForkFromSelectedUserEntryKeepsEarlierContextOnly() async throws {
        let session = SKIAgentSession(client: AgentEchoClient())
        _ = try await session.prompt("one")
        _ = try await session.prompt("two")
        _ = try await session.prompt("three")

        let messages = await session.forkableUserMessages()
        XCTAssertEqual(messages.count, 3)
        let forked = try await session.fork(fromUserEntryIndex: messages[1].entryIndex)
        let userTexts = userPromptTexts(from: await forked.transcriptEntries())
        XCTAssertEqual(userTexts, ["one"])

        let originTexts = userPromptTexts(from: await session.transcriptEntries())
        XCTAssertEqual(originTexts, ["one", "two", "three"])
    }

    func testForkFromInvalidUserEntryIndexThrowsDomainError() async throws {
        let session = SKIAgentSession(client: AgentEchoClient())
        _ = try await session.prompt("one")
        _ = try await session.prompt("two")

        do {
            _ = try await session.fork(fromUserEntryIndex: 999)
            XCTFail("expected invalid fork index")
        } catch let error as SKIAgentSessionError {
            XCTAssertEqual(error, .invalidForkEntryIndex(999))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testForkFromNonUserEntryIndexThrowsDomainError() async throws {
        let session = SKIAgentSession(client: AgentEchoClient())
        _ = try await session.prompt("one")

        let entries = await session.transcriptEntries()
        let nonUserIndex = try XCTUnwrap(entries.enumerated().first(where: { _, entry in
            switch entry {
            case .prompt(let message), .message(let message), .response(let message):
                return message.role != "user"
            case .toolCalls, .toolOutput:
                return true
            }
        })?.offset)

        do {
            _ = try await session.fork(fromUserEntryIndex: nonUserIndex)
            XCTFail("expected invalid fork index for non-user entry")
        } catch let error as SKIAgentSessionError {
            XCTAssertEqual(error, .invalidForkEntryIndex(nonUserIndex))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testPromptWithFollowUpBehaviorQueuesAndExecutesInOrder() async throws {
        let session = SKIAgentSession(client: AgentDelayEchoClient(delayNanos: 120_000_000))
        let firstTask = Task { try await session.prompt("first") }

        try await Task.sleep(nanoseconds: 20_000_000)
        let secondTask = Task {
            try await session.prompt("second", streamingBehavior: .followUp)
        }

        try await Task.sleep(nanoseconds: 20_000_000)
        let queuedCount = await session.pendingMessageCount()
        XCTAssertEqual(queuedCount, 1)
        let first = try await firstTask.value
        let second = try await secondTask.value
        XCTAssertTrue(first.contains("first"))
        XCTAssertTrue(second.contains("second"))
        let finalQueuedCount = await session.pendingMessageCount()
        XCTAssertEqual(finalQueuedCount, 0)

        let texts = userPromptTexts(from: await session.transcriptEntries())
        XCTAssertEqual(texts, ["first", "second"])
    }

    func testSteerQueuesFireAndForgetDuringActivePrompt() async throws {
        let session = SKIAgentSession(client: AgentDelayEchoClient(delayNanos: 100_000_000))
        let firstTask = Task { try await session.prompt("origin") }

        try await Task.sleep(nanoseconds: 20_000_000)
        await session.steer("steer-next")
        let queuedCount = await session.pendingMessageCount()
        XCTAssertEqual(queuedCount, 1)

        _ = try await firstTask.value
        try await Task.sleep(nanoseconds: 150_000_000)
        let finalQueuedCount = await session.pendingMessageCount()
        XCTAssertEqual(finalQueuedCount, 0)

        let texts = userPromptTexts(from: await session.transcriptEntries())
        XCTAssertEqual(texts, ["origin", "steer-next"])
    }

    func testFollowUpWhenIdleExecutesOnce() async throws {
        let session = SKIAgentSession(client: AgentEchoClient())

        await session.followUp("idle-follow")
        try await Task.sleep(nanoseconds: 80_000_000)

        let texts = userPromptTexts(from: await session.transcriptEntries())
        XCTAssertEqual(texts, ["idle-follow"])
    }

    func testFollowUpWhenIdleAppendsResolvedHistory() async throws {
        let session = SKIAgentSession(client: AgentDelayEchoClient(delayNanos: 80_000_000))

        await session.followUp("idle-follow")
        try await Task.sleep(nanoseconds: 140_000_000)

        let history = await session.pendingMessages(includeResolved: true)
        XCTAssertTrue(history.contains(where: {
            $0.source == .followUp && $0.status == .resolved && $0.textPreview == "idle-follow"
        }))
    }

    func testFollowUpWhenIdleFailureAppendsFailedHistory() async throws {
        let session = SKIAgentSession(client: AgentFailAfterDelayClient(delayNanos: 80_000_000))

        await session.followUp("idle-fail")
        try await Task.sleep(nanoseconds: 140_000_000)

        let history = await session.pendingMessages(includeResolved: true)
        XCTAssertTrue(history.contains(where: {
            $0.source == .followUp && $0.status == .failed && $0.textPreview == "idle-fail"
        }))
    }

    func testSteerWhenIdleAppendsResolvedHistory() async throws {
        let session = SKIAgentSession(client: AgentDelayEchoClient(delayNanos: 80_000_000))

        await session.steer("idle-steer")
        try await Task.sleep(nanoseconds: 140_000_000)

        let history = await session.pendingMessages(includeResolved: true)
        XCTAssertTrue(history.contains(where: {
            $0.source == .steer && $0.status == .resolved && $0.textPreview == "idle-steer"
        }))
    }

    func testSteerWhenIdleFailureAppendsFailedHistory() async throws {
        let session = SKIAgentSession(client: AgentFailAfterDelayClient(delayNanos: 80_000_000))

        await session.steer("idle-steer-fail")
        try await Task.sleep(nanoseconds: 140_000_000)

        let history = await session.pendingMessages(includeResolved: true)
        XCTAssertTrue(history.contains(where: {
            $0.source == .steer && $0.status == .failed && $0.textPreview == "idle-steer-fail"
        }))
    }

    func testToolDescriptorsExposeMetadataAndEnabledState() async throws {
        let session = SKIAgentSession(
            client: AgentEchoClient(),
            tools: [SessionEnabledTool(), SessionDisabledTool()]
        )

        let descriptors = await session.toolDescriptors()
        XCTAssertEqual(descriptors.count, 2)

        let enabled = try XCTUnwrap(descriptors.first(where: { $0.name == "session_enabled_tool" }))
        XCTAssertEqual(enabled.shortDescription, "enabled short")
        XCTAssertEqual(enabled.source, .native)
        XCTAssertEqual(enabled.isEnabled, true)
        XCTAssertNotNil(enabled.parameters?["type"])

        let disabled = try XCTUnwrap(descriptors.first(where: { $0.name == "session_disabled_tool" }))
        XCTAssertEqual(disabled.isEnabled, false)
        XCTAssertEqual(disabled.shortDescription, "disabled short")
    }

    func testActiveToolNamesAndUnregisterReflectCurrentState() async throws {
        let session = SKIAgentSession(
            client: AgentEchoClient(),
            tools: [SessionEnabledTool(), SessionDisabledTool()]
        )

        let activeBefore = await session.activeToolNames()
        XCTAssertEqual(activeBefore, ["session_enabled_tool"])

        await session.unregister(toolNamed: "session_enabled_tool")
        let activeAfter = await session.activeToolNames()
        XCTAssertEqual(activeAfter, [])

        let descriptorsAfter = await session.toolDescriptors()
        XCTAssertEqual(descriptorsAfter.count, 1)
        XCTAssertEqual(descriptorsAfter.first?.name, "session_disabled_tool")
    }

    func testMCPToolDescriptorsAndUnregisterReflectCurrentState() async throws {
        let session = SKIAgentSession(client: AgentEchoClient())
        let mcpClient = SKIMCPClient(endpoint: URL(string: "http://localhost")!)
        let mcpTool = SKIMCPTool(
            mcpTool: .init(
                name: "mcp_echo_tool",
                description: "mcp tool",
                inputSchema: .object([:])
            ),
            client: mcpClient
        )

        await session.register(mcpTool: mcpTool)

        let activeBefore = await session.activeToolNames()
        XCTAssertEqual(activeBefore, ["mcp_echo_tool"])

        let descriptorsBefore = await session.toolDescriptors()
        let mcpDescriptor = try XCTUnwrap(descriptorsBefore.first(where: { $0.name == "mcp_echo_tool" }))
        XCTAssertEqual(mcpDescriptor.source, .mcp)
        XCTAssertEqual(mcpDescriptor.isEnabled, true)

        await session.unregister(mcpToolNamed: "mcp_echo_tool")

        let activeAfter = await session.activeToolNames()
        XCTAssertEqual(activeAfter, [])
        let descriptorsAfter = await session.toolDescriptors()
        XCTAssertFalse(descriptorsAfter.contains(where: { $0.name == "mcp_echo_tool" }))
    }

    func testSessionStatsCountsMessagesAndToolLifecycle() async throws {
        let session = SKIAgentSession(
            client: AgentToolFlowClient(),
            tools: [SessionEnabledTool()]
        )

        _ = try await session.prompt("calc")
        let stats = await session.stats()

        XCTAssertEqual(stats.userMessages, 1)
        XCTAssertEqual(stats.assistantMessages, 1)
        XCTAssertEqual(stats.toolCalls, 1)
        XCTAssertEqual(stats.toolResults, 1)
        XCTAssertEqual(stats.totalEntries, 4)
        XCTAssertEqual(stats.pendingMessages, 0)
        XCTAssertTrue(stats.sessionId.hasPrefix("sess_"))
    }

    func testPendingMessagesSnapshotIncludesSourceAndPreview() async throws {
        let session = SKIAgentSession(client: AgentDelayEchoClient(delayNanos: 200_000_000))
        let firstTask = Task { try await session.prompt("origin") }

        try await Task.sleep(nanoseconds: 20_000_000)
        let followUpTask = Task {
            try await session.prompt("queued-prompt", streamingBehavior: .followUp)
        }
        try await Task.sleep(nanoseconds: 20_000_000)
        await session.steer("queued-steer")
        await session.followUp("queued-follow")

        try await Task.sleep(nanoseconds: 20_000_000)
        let pending = await session.pendingMessages()
        XCTAssertEqual(pending.count, 3)
        XCTAssertEqual(pending.map(\.source), [.promptFollowUp, .steer, .followUp])
        XCTAssertEqual(pending.map(\.textPreview), ["queued-prompt", "queued-steer", "queued-follow"])

        _ = try await firstTask.value
        _ = try await followUpTask.value
        try await Task.sleep(nanoseconds: 450_000_000)
        let finalCount = await session.pendingMessageCount()
        XCTAssertEqual(finalCount, 0)
    }

    func testSessionStatsPendingBreakdownCountsBySource() async throws {
        let session = SKIAgentSession(client: AgentDelayEchoClient(delayNanos: 220_000_000))
        let firstTask = Task { try await session.prompt("origin") }

        try await Task.sleep(nanoseconds: 20_000_000)
        let followUpTask = Task {
            try await session.prompt("queued-prompt", streamingBehavior: .followUp)
        }
        try await Task.sleep(nanoseconds: 20_000_000)
        await session.steer("queued-steer")
        await session.followUp("queued-follow")
        try await Task.sleep(nanoseconds: 20_000_000)

        let midStats = await session.stats()
        XCTAssertEqual(midStats.pendingMessages, 3)
        XCTAssertEqual(midStats.pendingBreakdown.promptFollowUp, 1)
        XCTAssertEqual(midStats.pendingBreakdown.steer, 1)
        XCTAssertEqual(midStats.pendingBreakdown.followUp, 1)

        _ = try await firstTask.value
        _ = try await followUpTask.value
        try await Task.sleep(nanoseconds: 500_000_000)

        let finalStats = await session.stats()
        XCTAssertEqual(finalStats.pendingMessages, 0)
        XCTAssertEqual(finalStats.pendingBreakdown.promptFollowUp, 0)
        XCTAssertEqual(finalStats.pendingBreakdown.steer, 0)
        XCTAssertEqual(finalStats.pendingBreakdown.followUp, 0)
    }

    func testSessionStatsLastUpdatedAtIsNilWhenEmptyAndAdvancesAfterUpdates() async throws {
        let session = SKIAgentSession(client: AgentEchoClient())
        let initialStats = await session.stats()
        XCTAssertNil(initialStats.lastUpdatedAt)

        _ = try await session.prompt("first")
        let afterFirst = await session.stats()
        let firstUpdatedAt = try XCTUnwrap(afterFirst.lastUpdatedAt)

        try await Task.sleep(nanoseconds: 10_000_000)
        _ = try await session.prompt("second")
        let afterSecond = await session.stats()
        let secondUpdatedAt = try XCTUnwrap(afterSecond.lastUpdatedAt)
        XCTAssertGreaterThanOrEqual(secondUpdatedAt.timeIntervalSince1970, firstUpdatedAt.timeIntervalSince1970)
    }

    func testPendingMessagesPreviewUsesStableMaxLength() async throws {
        let session = SKIAgentSession(client: AgentDelayEchoClient(delayNanos: 180_000_000))
        let firstTask = Task { try await session.prompt("origin") }
        let longText = String(repeating: "x", count: 150)

        try await Task.sleep(nanoseconds: 20_000_000)
        await session.followUp(longText)
        try await Task.sleep(nanoseconds: 20_000_000)

        let pending = await session.pendingMessages()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].source, .followUp)
        XCTAssertTrue(pending[0].textPreview.hasSuffix("..."))
        XCTAssertEqual(pending[0].textPreview.count, 123)

        _ = try await firstTask.value
    }

    func testPendingMessagesSupportsCustomPreviewMaxLength() async throws {
        let session = SKIAgentSession(client: AgentDelayEchoClient(delayNanos: 180_000_000))
        let firstTask = Task { try await session.prompt("origin") }
        let longText = String(repeating: "y", count: 50)

        try await Task.sleep(nanoseconds: 20_000_000)
        await session.followUp(longText)
        try await Task.sleep(nanoseconds: 20_000_000)

        let pending = await session.pendingMessages(maxLength: 10)
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].textPreview, "yyyyyyyyyy...")
        XCTAssertEqual(pending[0].textPreview.count, 13)

        _ = try await firstTask.value
    }

    func testPendingMessagesCanIncludeResolvedHistory() async throws {
        let session = SKIAgentSession(client: AgentDelayEchoClient(delayNanos: 180_000_000))
        let firstTask = Task { try await session.prompt("origin") }
        try await Task.sleep(nanoseconds: 20_000_000)
        let followUpTask = Task {
            try await session.prompt("queued-follow-up", streamingBehavior: .followUp)
        }

        try await Task.sleep(nanoseconds: 20_000_000)
        let queuedOnly = await session.pendingMessages()
        XCTAssertTrue(queuedOnly.allSatisfy { $0.status == .queued })

        _ = try await firstTask.value
        _ = try await followUpTask.value
        try await Task.sleep(nanoseconds: 50_000_000)

        let currentQueued = await session.pendingMessages()
        XCTAssertEqual(currentQueued.count, 0)

        let withResolved = await session.pendingMessages(includeResolved: true)
        XCTAssertTrue(withResolved.contains(where: {
            $0.source == .promptFollowUp
                && $0.status == .resolved
                && $0.textPreview.contains("queued-follow-up")
        }))
    }

    func testPendingMessagesIncludeResolvedHonorsCustomPreviewMaxLength() async throws {
        let session = SKIAgentSession(client: AgentDelayEchoClient(delayNanos: 180_000_000))
        let firstTask = Task { try await session.prompt("origin") }
        let longText = String(repeating: "z", count: 50)

        try await Task.sleep(nanoseconds: 20_000_000)
        let followUpTask = Task {
            try await session.prompt(longText, streamingBehavior: .followUp)
        }

        _ = try await firstTask.value
        _ = try await followUpTask.value
        try await Task.sleep(nanoseconds: 50_000_000)

        let withResolved = await session.pendingMessages(maxLength: 10, includeResolved: true)
        let resolved = try XCTUnwrap(withResolved.first(where: { $0.status == .resolved }))
        XCTAssertEqual(resolved.textPreview, "zzzzzzzzzz...")
        XCTAssertEqual(resolved.textPreview.count, 13)
    }

    func testPendingMessagesIncludeResolvedCanUseLargerPreviewThanDefault() async throws {
        let session = SKIAgentSession(client: AgentDelayEchoClient(delayNanos: 180_000_000))
        let firstTask = Task { try await session.prompt("origin") }
        let longText = String(repeating: "a", count: 150)

        try await Task.sleep(nanoseconds: 20_000_000)
        let followUpTask = Task {
            try await session.prompt(longText, streamingBehavior: .followUp)
        }

        _ = try await firstTask.value
        _ = try await followUpTask.value
        try await Task.sleep(nanoseconds: 50_000_000)

        let withResolved = await session.pendingMessages(maxLength: 140, includeResolved: true)
        let resolved = try XCTUnwrap(withResolved.first(where: { $0.status == .resolved }))
        XCTAssertEqual(resolved.textPreview.count, 143)
        XCTAssertTrue(resolved.textPreview.hasSuffix("..."))
    }

    func testClearPendingHistoryOnlyRemovesResolvedItems() async throws {
        let session = SKIAgentSession(client: AgentDelayEchoClient(delayNanos: 180_000_000))
        let firstTask = Task { try await session.prompt("origin") }
        try await Task.sleep(nanoseconds: 20_000_000)
        let followUpTask = Task {
            try await session.prompt("queued-follow-up", streamingBehavior: .followUp)
        }
        _ = try await firstTask.value
        _ = try await followUpTask.value
        try await Task.sleep(nanoseconds: 50_000_000)

        let beforeClear = await session.pendingMessages(includeResolved: true)
        XCTAssertTrue(beforeClear.contains(where: { $0.status == .resolved }))

        await session.clearPendingHistory()
        let afterClear = await session.pendingMessages(includeResolved: true)
        XCTAssertFalse(afterClear.contains(where: { $0.status == .resolved }))
    }

    func testClearPendingStateCancelsQueuedFollowUpContinuations() async throws {
        let session = SKIAgentSession(client: AgentDelayEchoClient(delayNanos: 250_000_000))
        let firstTask = Task { try await session.prompt("origin") }
        try await Task.sleep(nanoseconds: 20_000_000)
        let followUpTask = Task {
            try await session.prompt("queued-follow-up", streamingBehavior: .followUp)
        }

        try await waitForPendingCount(
            expected: 1,
            in: session,
            timeoutNanos: 600_000_000
        )
        let clearResult = await session.clearPendingState()
        XCTAssertEqual(clearResult.queuedRemoved, 1)
        XCTAssertGreaterThanOrEqual(clearResult.resolvedRemoved, 0)
        XCTAssertFalse(clearResult.activePromptCancelled)

        do {
            _ = try await followUpTask.value
            XCTFail("expected cancelled follow-up continuation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }

        _ = try? await firstTask.value
        let pending = await session.pendingMessages(includeResolved: true)
        XCTAssertEqual(pending.count, 0)
    }

    func testClearPendingStateCanCancelActivePromptWhenRequested() async throws {
        let session = SKIAgentSession(client: AgentSlowClient())
        let running = Task { try await session.prompt("running") }

        try await Task.sleep(nanoseconds: 30_000_000)
        let clearResult = await session.clearPendingState(cancelActivePrompt: true)
        XCTAssertTrue(clearResult.activePromptCancelled)
        XCTAssertGreaterThanOrEqual(clearResult.queuedRemoved, 0)

        do {
            _ = try await running.value
            XCTFail("expected active prompt to be cancelled")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }

        let pending = await session.pendingMessages(includeResolved: true)
        XCTAssertEqual(pending.count, 0)
    }

    func testClearPendingStateResultDoesNotReportCancelledWhenNoActivePrompt() async throws {
        let session = SKIAgentSession(client: AgentEchoClient())
        let result = await session.clearPendingState(cancelActivePrompt: true)
        XCTAssertEqual(result.queuedRemoved, 0)
        XCTAssertEqual(result.resolvedRemoved, 0)
        XCTAssertFalse(result.activePromptCancelled)
    }

    func testCancelActivePromptMarksQueuedPendingAsFailedInHistory() async throws {
        let session = SKIAgentSession(client: AgentDelayEchoClient(delayNanos: 220_000_000))
        let firstTask = Task { try await session.prompt("origin") }

        try await Task.sleep(nanoseconds: 20_000_000)
        let queuedFollowUpTask = Task {
            try await session.prompt("queued-follow-up", streamingBehavior: .followUp)
        }
        await session.steer("queued-steer")

        try await waitForPendingCount(expected: 2, in: session, timeoutNanos: 300_000_000)
        await session.cancelActivePrompt()

        do {
            _ = try await firstTask.value
            XCTFail("expected active prompt cancelled")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }

        do {
            _ = try await queuedFollowUpTask.value
            XCTFail("expected queued follow-up cancelled")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }

        let history = await session.pendingMessages(includeResolved: true)
        XCTAssertTrue(history.contains(where: {
            $0.source == .promptFollowUp && $0.status == .failed
        }))
        XCTAssertTrue(history.contains(where: {
            $0.source == .steer && $0.status == .failed
        }))
    }

    func testClearPendingStateWithCancelActivePromptKeepsResolvedHistoryEmptyAfterQueueDrop() async throws {
        let session = SKIAgentSession(client: AgentDelayEchoClient(delayNanos: 260_000_000))
        let firstTask = Task { try await session.prompt("origin") }

        try await Task.sleep(nanoseconds: 20_000_000)
        await session.followUp("queued-fire")
        let queuedAwaitingTask = Task {
            try await session.prompt("queued-awaiting", streamingBehavior: .followUp)
        }

        try await waitForPendingCount(expected: 2, in: session, timeoutNanos: 400_000_000)
        let clearResult = await session.clearPendingState(cancelActivePrompt: true)
        XCTAssertEqual(clearResult.queuedRemoved, 2)
        XCTAssertTrue(clearResult.activePromptCancelled)

        do {
            _ = try await firstTask.value
            XCTFail("expected active prompt cancelled")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }

        do {
            _ = try await queuedAwaitingTask.value
            XCTFail("expected queued awaiting cancelled")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }

        try await Task.sleep(nanoseconds: 80_000_000)
        let history = await session.pendingMessages(includeResolved: true)
        XCTAssertEqual(history.count, 0)
    }

    func testResolvedPendingHistoryLimitKeepsLatestFailedItems() async throws {
        let session = SKIAgentSession(client: AgentDelayEchoClient(delayNanos: 800_000_000))
        let firstTask = Task { try await session.prompt("origin") }

        try await Task.sleep(nanoseconds: 20_000_000)
        for i in 0..<25 {
            let text = String(format: "queued-%02d", i)
            await session.followUp(text)
        }

        try await waitForPendingCount(expected: 25, in: session, timeoutNanos: 300_000_000)

        await session.cancelActivePrompt()

        do {
            _ = try await firstTask.value
            XCTFail("expected active prompt cancelled")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }

        let history = await session.pendingMessages(includeResolved: true)
        XCTAssertEqual(history.count, SKIAgentSession.resolvedPendingHistoryLimit)
        XCTAssertTrue(history.allSatisfy { $0.status == .failed && $0.source == .followUp })

        let previews = history.map(\.textPreview)
        XCTAssertFalse(previews.contains("queued-00"))
        XCTAssertFalse(previews.contains("queued-01"))
        XCTAssertFalse(previews.contains("queued-02"))
        XCTAssertFalse(previews.contains("queued-03"))
        XCTAssertFalse(previews.contains("queued-04"))
        XCTAssertEqual(previews.first, "queued-05")
        XCTAssertEqual(previews.last, "queued-24")
    }

    func testUpstreamFailureMarksAwaitingAndFireAndForgetAsFailed() async throws {
        let session = SKIAgentSession(client: AgentFailAfterDelayClient(delayNanos: 220_000_000))
        let firstTask = Task { try await session.prompt("origin") }

        try await Task.sleep(nanoseconds: 20_000_000)
        let awaitingTask = Task {
            try await session.prompt("queued-awaiting", streamingBehavior: .followUp)
        }
        await session.followUp("queued-fire")

        try await waitForPendingCount(expected: 2, in: session, timeoutNanos: 300_000_000)

        do {
            _ = try await firstTask.value
            XCTFail("expected upstream failure")
        } catch {
            XCTAssertEqual(error as? AgentFailAfterDelayClient.TestError, .upstreamFailed)
        }

        do {
            _ = try await awaitingTask.value
            XCTFail("expected awaiting task failed with upstream error")
        } catch {
            XCTAssertEqual(error as? AgentFailAfterDelayClient.TestError, .upstreamFailed)
        }

        let history = await session.pendingMessages(includeResolved: true)
        XCTAssertTrue(history.contains(where: {
            $0.source == .promptFollowUp && $0.status == .failed && $0.textPreview == "queued-awaiting"
        }))
        XCTAssertTrue(history.contains(where: {
            $0.source == .followUp && $0.status == .failed && $0.textPreview == "queued-fire"
        }))
    }

    private func waitForPendingCount(
        expected: Int,
        in session: SKIAgentSession,
        timeoutNanos: UInt64
    ) async throws {
        let start = DispatchTime.now().uptimeNanoseconds
        while DispatchTime.now().uptimeNanoseconds - start < timeoutNanos {
            if await session.pendingMessageCount() == expected {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("pending count did not reach \(expected) within timeout")
    }
}

private func userPromptTexts(from entries: [SKITranscript.Entry]) -> [String] {
    entries.compactMap { entry -> String? in
        guard case .prompt(let message) = entry else { return nil }
        guard case .user(let content, _) = message else { return nil }
        switch content {
        case .text(let text):
            return text
        case .parts(let parts):
            let values = parts.compactMap { part -> String? in
                if case .text(let text) = part {
                    return text
                }
                return nil
            }
            return values.isEmpty ? nil : values.joined(separator: "\n")
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

private struct AgentDelayEchoClient: SKILanguageModelClient {
    let delayNanos: UInt64

    func respond(_ body: ChatRequestBody) async throws -> sending SKIResponse<ChatResponseBody> {
        try await Task.sleep(nanoseconds: delayNanos)
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

private struct AgentFailAfterDelayClient: SKILanguageModelClient {
    enum TestError: Error, Equatable {
        case upstreamFailed
    }

    let delayNanos: UInt64

    func respond(_ body: ChatRequestBody) async throws -> sending SKIResponse<ChatResponseBody> {
        _ = body
        try await Task.sleep(nanoseconds: delayNanos)
        throw TestError.upstreamFailed
    }
}

private struct SessionEnabledTool: SKITool {
    let name = "session_enabled_tool"
    let description = "enabled tool description"
    let shortDescription = "enabled short"
    let isEnabled = true

    @Schemable
    struct Arguments: Codable {
        let input: String
    }

    struct ToolOutput: Codable {
        let value: String
    }

    func call(_ arguments: Arguments) async throws -> ToolOutput {
        .init(value: arguments.input)
    }
}

private struct SessionDisabledTool: SKITool {
    let name = "session_disabled_tool"
    let description = "disabled tool description"
    let shortDescription = "disabled short"
    let isEnabled = false

    @Schemable
    struct Arguments: Codable {
        let input: String
    }

    struct ToolOutput: Codable {
        let value: String
    }

    func call(_ arguments: Arguments) async throws -> ToolOutput {
        .init(value: arguments.input)
    }
}

private final class AgentToolFlowClient: SKILanguageModelClient {
    private var callCount = 0

    func respond(_ body: ChatRequestBody) async throws -> sending SKIResponse<ChatResponseBody> {
        _ = body
        callCount += 1
        if callCount == 1 {
            let payload = """
            {
              "choices": [
                {
                  "finish_reason": "tool_calls",
                  "message": {
                    "role": "assistant",
                    "tool_calls": [
                      {
                        "id": "call_1",
                        "type": "function",
                        "function": {
                          "name": "session_enabled_tool",
                          "arguments": "{\\"input\\":\\"42\\"}"
                        }
                      }
                    ]
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

        let payload = """
        {
          "choices": [
            {
              "finish_reason": "stop",
              "message": {
                "content": "done",
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
