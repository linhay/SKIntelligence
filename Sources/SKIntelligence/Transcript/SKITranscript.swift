//
//  SKITranscript.swift
//  SKIntelligence
//
//  Created by linhey on 11/4/25.
//

import Foundation

public actor SKITranscript {

    public typealias OrganizeEntriesAction = @Sendable (_ entries: [Entry]) async throws -> [Entry]
    public typealias ObserveNewEntryBlock = @Sendable (_ entry: Entry) async throws -> Void

    public struct ObserveNewEntry {

        public static func print(prefix: String = "") -> ObserveNewEntry {
            .init { entry in
                let prefixStr = prefix.isEmpty ? "" : "[\(prefix)] "
                switch entry {
                case .message(let content):
                    Swift.print("\(prefixStr)[message] \(content)")
                case .prompt(_):
                    break
                //                    Swift.print("\(prefixStr)[prompt] \(content)")
                case .response(let content):
                    Swift.print("\(prefixStr)[response] \(content)")
                case .toolCalls(let call):
                    Swift.print(
                        "\(prefixStr)[toolCall] id: \(call.id), function: \(call.function.name), arguments: \(call.function.arguments ?? "")"
                    )
                case .toolOutput(let output):
                    Swift.print(
                        "\(prefixStr)[toolOutput] toolCallId: \(output.toolCall.id), content: \(output.content)"
                    )
                }
            }
        }

        public let block: ObserveNewEntryBlock
        public init(block: @escaping ObserveNewEntryBlock) {
            self.block = block
        }
    }

    public struct ToolOutput {
        public let content: ChatRequestBody.Message.MessageContent<String, [String]>
        public let toolCall: ChatRequestBody.Message.ToolCall

        public init(
            content: ChatRequestBody.Message.MessageContent<String, [String]>,
            toolCall: ChatRequestBody.Message.ToolCall
        ) {
            self.content = content
            self.toolCall = toolCall
        }

        /// Extracts string content from the tool output.
        public var contentString: String {
            switch content {
            case .text(let text):
                return text
            case .parts(let parts):
                return parts.joined(separator: "\n")
            }
        }
    }

    public enum Entry {
        case prompt(ChatRequestBody.Message)
        case message(ChatRequestBody.Message)
        case response(ChatRequestBody.Message)

        case toolCalls(ChatRequestBody.Message.ToolCall)
        case toolOutput(ToolOutput)

        /// Converts this entry to a SKIMemoryMessage.
        ///
        /// - Returns: The equivalent memory message, or nil if conversion is not applicable.
        public func toMemoryMessage() -> SKIMemoryMessage? {
            switch self {
            case .prompt(let msg), .message(let msg), .response(let msg):
                return SKIMemoryMessage(from: msg)
            case .toolCalls(let call):
                return .tool(
                    "Tool call: \(call.function.name)(\(call.function.arguments ?? ""))",
                    toolName: call.function.name)
            case .toolOutput(let output):
                return .tool(output.contentString, toolName: output.toolCall.function.name)
            }
        }
    }

    public private(set) var entries: [Entry] = []
    public private(set) var lastUpdatedAt: Date?
    public private(set) var organizeEntries: OrganizeEntriesAction?
    public private(set) var observeNewEntry: ObserveNewEntry?

    /// Optional memory for persisting conversation history.
    public internal(set) var memory: (any SKIMemory)?
    /// Whether to automatically sync entries to memory.
    public var syncToMemory: Bool = true

    public init() {}

}

extension SKITranscript {

    public func replaceEntries(_ newEntries: [Entry]) {
        entries = newEntries
        lastUpdatedAt = newEntries.isEmpty ? nil : Date()
    }

    public func runOrganizeEntries() async throws {
        if let entries = try await organizeEntries?(entries) {
            self.entries = entries
        }
    }

    /// 整理记录
    public func setOrganizeEntries(_ block: OrganizeEntriesAction?) {
        organizeEntries = block
    }

    public func runObserveNewEntry(_ entry: Entry) async throws {
        try await observeNewEntry?.block(entry)
    }

    /// 监听新记录
    public func setObserveNewEntry(_ block: ObserveNewEntry?) {
        observeNewEntry = block
    }

}

extension SKITranscript {

    /// Adds an observe block without overwriting an existing observer.
    ///
    /// If an observer already exists, this composes them in-order.
    public func addObserveNewEntry(_ observer: ObserveNewEntry) {
        if let existing = observeNewEntry {
            observeNewEntry = .init { entry in
                try await existing.block(entry)
                try await observer.block(entry)
            }
        } else {
            observeNewEntry = observer
        }
    }
}

extension SKITranscript {

    public func messages() async throws -> [ChatRequestBody.Message] {
        var list = [ChatRequestBody.Message]()
        for entry in self.entries {
            switch entry {
            case .message(let message), .response(let message), .prompt(let message):
                list.append(message)
            case .toolCalls(let toolCall):
                list.append(.assistant(toolCalls: [toolCall]))
            case .toolOutput(let toolOutput):
                list.append(.tool(content: toolOutput.content, toolCallID: toolOutput.toolCall.id))
            }
        }
        return list
    }

}

extension SKITranscript {

    /// Appends a single entry to the transcript.
    public func append(entry: Entry) async throws {
        entries.append(entry)
        lastUpdatedAt = Date()
        try await runObserveNewEntry(entry)

        // Sync to memory if enabled
        if syncToMemory, let memory = memory, let memoryMessage = entry.toMemoryMessage() {
            await memory.add(memoryMessage)
        }
    }

    public func append(toolOutput entry: ToolOutput) async throws {
        try await append(entry: .toolOutput(entry))
    }

    public func append(toolCalls entry: ChatRequestBody.Message.ToolCall) async throws {
        try await append(entry: .toolCalls(entry))
    }

    public func append(message entry: ChatRequestBody.Message) async throws {
        try await append(entry: .message(entry))
    }

    public func append(prompt entry: ChatRequestBody.Message) async throws {
        try await append(entry: .prompt(entry))
    }

    public func append(response entry: ChatRequestBody.Message) async throws {
        try await append(entry: .response(entry))
    }

    /// Appends multiple entries to the transcript.
    public func append<S>(contentsOf newEntries: S) async throws
    where S: Sequence, S.Element == Entry {
        for entry in newEntries {
            try await append(entry: entry)
        }
    }

}

extension SKITranscript {

    public subscript(_ index: Int) -> Entry {
        entries[index]
    }

    public var startIndex: Int {
        entries.startIndex
    }

    public var endIndex: Int {
        entries.endIndex
    }

}

// MARK: - Fork Helpers

extension SKITranscript {
    public struct ForkableUserMessage: Sendable, Equatable {
        public let entryIndex: Int
        public let text: String

        public init(entryIndex: Int, text: String) {
            self.entryIndex = entryIndex
            self.text = text
        }
    }

    public enum ForkSelectionError: Error, LocalizedError, Equatable {
        case invalidUserEntryIndex(Int)

        public var errorDescription: String? {
            switch self {
            case .invalidUserEntryIndex(let index):
                return "Invalid user entry index for fork: \(index)"
            }
        }
    }

    public func forkableUserMessages() -> [ForkableUserMessage] {
        entries.enumerated().compactMap { index, entry in
            guard let text = entry.forkableUserText else { return nil }
            return ForkableUserMessage(entryIndex: index, text: text)
        }
    }

    public func entriesForFork(fromUserEntryIndex index: Int) throws -> [Entry] {
        guard entries.indices.contains(index), entries[index].forkableUserText != nil else {
            throw ForkSelectionError.invalidUserEntryIndex(index)
        }
        return Array(entries[..<index])
    }
}

// MARK: - Event Contract

extension SKITranscript {
    public enum EventKind: String, Sendable, Equatable, Codable {
        case message
        case toolCall = "tool_call"
        case toolResult = "tool_result"
        case toolExecutionUpdate = "tool_execution_update"
        case sessionUpdate = "session_update"
    }

    public enum ToolExecutionState: String, Sendable, Equatable, Codable {
        case started
        case completed
        case failed
    }

    public enum EventSource: String, Sendable, Equatable, Codable {
        case transcript
        case session
    }

    public struct Event: Sendable, Equatable, Codable {
        public var kind: EventKind
        public var role: String?
        public var content: String?
        public var toolName: String?
        public var toolCallId: String?
        public var state: ToolExecutionState?
        public var sessionUpdateName: String?
        public var source: EventSource?
        public var entryIndex: Int?

        public init(
            kind: EventKind,
            role: String? = nil,
            content: String? = nil,
            toolName: String? = nil,
            toolCallId: String? = nil,
            state: ToolExecutionState? = nil,
            sessionUpdateName: String? = nil,
            source: EventSource? = nil,
            entryIndex: Int? = nil
        ) {
            self.kind = kind
            self.role = role
            self.content = content
            self.toolName = toolName
            self.toolCallId = toolCallId
            self.state = state
            self.sessionUpdateName = sessionUpdateName
            self.source = source
            self.entryIndex = entryIndex
        }
    }

    public static func events(from entry: Entry) -> [Event] {
        events(from: entry, entryIndex: nil)
    }

    public static func events(from entry: Entry, entryIndex: Int?) -> [Event] {
        switch entry {
        case .prompt(let msg), .message(let msg), .response(let msg):
            return [
                .init(
                    kind: .message,
                    role: msg.role,
                    content: msg.eventTextContent,
                    source: .transcript,
                    entryIndex: entryIndex
                )
            ]
        case .toolCalls(let call):
            return [
                .init(
                    kind: .toolCall,
                    content: call.function.arguments,
                    toolName: call.function.name,
                    toolCallId: call.id,
                    source: .transcript,
                    entryIndex: entryIndex
                ),
                .init(
                    kind: .toolExecutionUpdate,
                    toolName: call.function.name,
                    toolCallId: call.id,
                    state: .started,
                    source: .transcript,
                    entryIndex: entryIndex
                ),
            ]
        case .toolOutput(let output):
            return [
                .init(
                    kind: .toolResult,
                    content: output.contentString,
                    toolName: output.toolCall.function.name,
                    toolCallId: output.toolCall.id,
                    source: .transcript,
                    entryIndex: entryIndex
                ),
                .init(
                    kind: .toolExecutionUpdate,
                    toolName: output.toolCall.function.name,
                    toolCallId: output.toolCall.id,
                    state: .completed,
                    source: .transcript,
                    entryIndex: entryIndex
                ),
            ]
        }
    }

    public static func sessionUpdateEvent(name: String, content: String? = nil) -> Event {
        .init(
            kind: .sessionUpdate,
            content: content,
            sessionUpdateName: name,
            source: .session
        )
    }

    public func events() -> [Event] {
        entries.enumerated().flatMap { index, entry in
            Self.events(from: entry, entryIndex: index)
        }
    }
}

private extension ChatRequestBody.Message {
    var eventTextContent: String? {
        switch self {
        case .assistant(let content, _, _, _):
            return content?.eventTextValue
        case .developer(let content, _):
            return content.eventTextValue
        case .system(let content, _):
            return content.eventTextValue
        case .tool(let content, _):
            return content.eventTextValue
        case .user(let content, _):
            return content.eventTextValue
        }
    }
}

private extension ChatRequestBody.Message.MessageContent where SingleType == String, PartsType == [String] {
    var eventTextValue: String? {
        switch self {
        case .text(let value):
            return value
        case .parts(let values):
            return values.joined(separator: "\n")
        }
    }
}

private extension ChatRequestBody.Message.MessageContent where SingleType == String, PartsType == [ChatRequestBody.Message.ContentPart] {
    var eventTextValue: String? {
        switch self {
        case .text(let value):
            return value
        case .parts(let values):
            let textParts = values.compactMap { part -> String? in
                switch part {
                case .text(let text):
                    return text
                case .imageURL:
                    return nil
                }
            }
            if textParts.isEmpty { return nil }
            return textParts.joined(separator: "\n")
        }
    }
}

private extension SKITranscript.Entry {
    var forkableUserText: String? {
        switch self {
        case .prompt(let message), .message(let message), .response(let message):
            return message.forkableUserText
        case .toolCalls, .toolOutput:
            return nil
        }
    }
}

private extension ChatRequestBody.Message {
    var forkableUserText: String? {
        guard case .user(let content, _) = self else { return nil }
        switch content {
        case .text(let value):
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case .parts(let parts):
            let values = parts.compactMap { part -> String? in
                guard case .text(let text) = part else { return nil }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            return values.isEmpty ? nil : values.joined(separator: "\n")
        }
    }
}

// MARK: - JSONL

extension SKITranscript {
    /// JSONL (ndjson) encoding/decoding utilities for persisting a transcript.
    ///
    /// The format is OpenClaw-compatible:
    /// - First line: `{"type":"session","version":1,"id":"...","timestamp":"...","cwd":"..."}`
    /// - Following: `{"message":{...}}`
    public enum JSONL {}
}

extension SKITranscript.JSONL {
    public struct Header: Sendable, Codable, Equatable {
        public var type: String
        public var version: Int
        public var id: String
        public var timestamp: String?
        public var cwd: String?

        public init(type: String = "session", version: Int = 1, id: String, timestamp: String? = nil, cwd: String? = nil) {
            self.type = type
            self.version = version
            self.id = id
            self.timestamp = timestamp
            self.cwd = cwd
        }
    }

    public struct ToolCallFunction: Sendable, Codable, Equatable {
        public var name: String
        public var arguments: String?

        public init(name: String, arguments: String? = nil) {
            self.name = name
            self.arguments = arguments
        }
    }

    public struct ToolCall: Sendable, Codable, Equatable {
        public var id: String
        public var type: String?
        public var function: ToolCallFunction

        public init(id: String, type: String? = "function", function: ToolCallFunction) {
            self.id = id
            self.type = type
            self.function = function
        }
    }

    public enum MessageContent: Sendable, Equatable, Codable {
        case text(String)
        case parts([TextPart])

        public struct TextPart: Sendable, Equatable, Codable {
            public var type: String
            public var text: String?

            public init(type: String = "text", text: String?) {
                self.type = type
                self.text = text
            }
        }

        public var stringValue: String? {
            switch self {
            case .text(let value):
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            case .parts(let parts):
                let items = parts.compactMap { part -> String? in
                    guard let t = part.text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
                    return t
                }
                guard !items.isEmpty else { return nil }
                return items.joined(separator: "\n")
            }
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let str = try? container.decode(String.self) {
                self = .text(str)
                return
            }
            let parts = try container.decode([TextPart].self)
            self = .parts(parts)
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .text(let value):
                try container.encode(value)
            case .parts(let parts):
                try container.encode(parts)
            }
        }
    }

    public struct Message: Sendable, Codable, Equatable {
        public var role: String
        public var content: MessageContent?
        public var name: String?
        public var toolCalls: [ToolCall]?
        public var toolCallId: String?

        public init(
            role: String,
            content: MessageContent? = nil,
            name: String? = nil,
            toolCalls: [ToolCall]? = nil,
            toolCallId: String? = nil
        ) {
            self.role = role
            self.content = content
            self.name = name
            self.toolCalls = toolCalls
            self.toolCallId = toolCallId
        }

        private enum CodingKeys: String, CodingKey {
            case role
            case content
            case name
            case toolCalls = "tool_calls"
            case toolCallId = "tool_call_id"
        }
    }

    public enum Line: Sendable, Equatable, Codable {
        case header(Header)
        case message(Message)

        private enum CodingKeys: String, CodingKey {
            case type
            case version
            case id
            case timestamp
            case cwd
            case message
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let msg = try container.decodeIfPresent(Message.self, forKey: .message) {
                self = .message(msg)
                return
            }
            let type = (try? container.decode(String.self, forKey: .type)) ?? "session"
            let version = (try? container.decode(Int.self, forKey: .version)) ?? 1
            let id = (try? container.decode(String.self, forKey: .id)) ?? ""
            let ts = try? container.decodeIfPresent(String.self, forKey: .timestamp)
            let cwd = try? container.decodeIfPresent(String.self, forKey: .cwd)
            self = .header(.init(type: type, version: version, id: id, timestamp: ts ?? nil, cwd: cwd ?? nil))
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .message(let msg):
                try container.encode(msg, forKey: .message)
            case .header(let header):
                try container.encode(header.type, forKey: .type)
                try container.encode(header.version, forKey: .version)
                try container.encode(header.id, forKey: .id)
                try container.encodeIfPresent(header.timestamp, forKey: .timestamp)
                try container.encodeIfPresent(header.cwd, forKey: .cwd)
            }
        }
    }
}

extension SKITranscript.JSONL {
    public static func message(from entry: SKITranscript.Entry) -> Message? {
        switch entry {
        case .prompt(let msg), .message(let msg), .response(let msg):
            return Message(chatMessage: msg)
        case .toolCalls(let toolCall):
            let call = ToolCall(
                id: toolCall.id,
                type: toolCall.type,
                function: .init(name: toolCall.function.name, arguments: toolCall.function.arguments)
            )
            return .init(role: "assistant", content: nil, toolCalls: [call])
        case .toolOutput(let output):
            return .init(role: "tool", content: .text(output.contentString), toolCallId: output.toolCall.id)
        }
    }
}

extension SKITranscript.JSONL.Message {
    public init?(chatMessage: ChatRequestBody.Message) {
        switch chatMessage {
        case .assistant(let content, let name, _, let toolCalls):
            let text = content.map { Self.convertMessageContentToTranscriptContent($0) }
            let calls = toolCalls?.map {
                SKITranscript.JSONL.ToolCall(
                    id: $0.id,
                    type: $0.type,
                    function: .init(name: $0.function.name, arguments: $0.function.arguments)
                )
            }
            self = .init(role: "assistant", content: text, name: name, toolCalls: calls)
        case .developer(let content, let name):
            self = .init(role: "developer", content: Self.convertMessageContentToTranscriptContent(content), name: name)
        case .system(let content, let name):
            self = .init(role: "system", content: Self.convertMessageContentToTranscriptContent(content), name: name)
        case .tool(let content, let toolCallId):
            self = .init(role: "tool", content: Self.convertMessageContentToTranscriptContent(content), toolCallId: toolCallId)
        case .user(let content, let name):
            self = .init(role: "user", content: Self.convertMessageContentToTranscriptContent(content), name: name)
        }
    }

    public func toChatMessage() -> ChatRequestBody.Message? {
        let text = content?.stringValue ?? ""
        switch role.lowercased() {
        case "user":
            return .user(content: .text(text), name: name)
        case "assistant":
            let toolCalls = toolCalls?.map {
                ChatRequestBody.Message.ToolCall(
                    id: $0.id,
                    function: .init(name: $0.function.name, arguments: $0.function.arguments)
                )
            }
            let assistantContent: ChatRequestBody.Message.MessageContent<String, [String]>? = text.isEmpty ? nil : .text(text)
            return .assistant(content: assistantContent, name: name, toolCalls: toolCalls)
        case "system":
            return .system(content: .text(text), name: name)
        case "developer":
            return .developer(content: .text(text), name: name)
        case "tool":
            return .tool(content: .text(text), toolCallID: toolCallId ?? "")
        default:
            return nil
        }
    }

    private static func convertMessageContentToTranscriptContent(
        _ content: ChatRequestBody.Message.MessageContent<String, [String]>
    ) -> SKITranscript.JSONL.MessageContent {
        switch content {
        case .text(let value):
            return .text(value)
        case .parts(let parts):
            let textParts = parts.compactMap { text -> SKITranscript.JSONL.MessageContent.TextPart? in
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                return .init(type: "text", text: trimmed)
            }
            if textParts.isEmpty { return .text("") }
            return .parts(textParts)
        }
    }

    private static func convertMessageContentToTranscriptContent(
        _ content: ChatRequestBody.Message.MessageContent<String, [ChatRequestBody.Message.ContentPart]>
    ) -> SKITranscript.JSONL.MessageContent {
        switch content {
        case .text(let value):
            return .text(value)
        case .parts(let parts):
            let textParts = parts.compactMap { part -> SKITranscript.JSONL.MessageContent.TextPart? in
                switch part {
                case .text(let text):
                    return .init(type: "text", text: text)
                case .imageURL:
                    return nil
                }
            }
            if textParts.isEmpty { return .text("") }
            return .parts(textParts)
        }
    }
}
