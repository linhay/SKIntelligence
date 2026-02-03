//
//  File.swift
//  SKIntelligence
//
//  Created by linhey on 12/29/25.
//

import Foundation
import STFilePath
import STJSON
// MARK: - Memory Management

extension SKITranscript {

    /// Sets the memory for persisting conversation history.
    ///
    /// - Parameter memory: The memory instance to use, or nil to disable.
    public func setMemory(_ memory: (any SKIMemory)?) {
        self.memory = memory
    }

    /// Loads conversation history from memory into entries.
    ///
    /// This converts stored `SKIMemoryMessage` back to transcript entries.
    /// Existing entries are preserved; memory messages are prepended.
    ///
    /// - Parameter limit: Maximum number of messages to load, nil for all.
    /// - Returns: The loaded memory messages.
    @discardableResult
    public func loadFromMemory(limit: Int? = nil) async -> [SKIMemoryMessage] {
        guard let memory = memory else { return [] }
        return await memory.context(for: "", maxMessages: limit)
    }

    /// Saves all current entries to memory.
    ///
    /// This is useful when you want to explicitly persist the current
    /// conversation state to memory.
    public func saveToMemory() async {
        guard let memory = memory else { return }
        for entry in entries {
            if let memoryMessage = entry.toMemoryMessage() {
                await memory.add(memoryMessage)
            }
        }
    }

    /// Clears the memory without affecting current entries.
    public func clearMemory() async {
        await memory?.clear()
    }

    /// Converts memory messages to ChatRequestBody.Message array.
    ///
    /// Useful for including memory context in API requests.
    ///
    /// - Parameter limit: Maximum number of messages to include.
    /// - Returns: Array of chat messages from memory.
    public func memoryMessages(limit: Int? = nil) async -> [ChatRequestBody.Message] {
        let memoryMsgs = await loadFromMemory(limit: limit)
        return memoryMsgs.map { $0.toChatMessage() }
    }
}

// MARK: - JSONL Transcript Persistence

extension SKITranscript {

    public struct JSONLPersistenceConfiguration: Sendable, Equatable {
        public var maxReadBytes: Int

        public init(maxReadBytes: Int = 256_000) {
            self.maxReadBytes = maxReadBytes
        }
    }

    /// Enables JSONL persistence for this transcript.
    ///
    /// This does three things:
    /// 1) Ensures the JSONL header exists (OpenClaw-compatible).
    /// 2) Loads messages from JSONL and replaces current entries.
    /// 3) Appends new transcript entries to JSONL via an observer.
    public func enableJSONLPersistence(
        sessionId: String,
        fileURL: URL,
        configuration: JSONLPersistenceConfiguration = .init()
    ) async throws {
        try Self.ensureJSONLHeader(sessionId: sessionId, fileURL: fileURL)

        let persisted = try Self.loadJSONLMessages(fileURL: fileURL, maxReadBytes: configuration.maxReadBytes)
        let loadedEntries: [SKITranscript.Entry] = persisted.compactMap { message in
            guard let chat = message.toChatMessage() else { return nil }
            return .message(chat)
        }
        replaceEntries(loadedEntries)

        addObserveNewEntry(.init { entry in
            guard let message = SKITranscript.JSONL.message(from: entry) else { return }
            try Self.appendJSONLMessage(message, sessionId: sessionId, fileURL: fileURL)
        })
    }

    public static func ensureJSONLHeader(sessionId: String, fileURL: URL) throws {
        let header = SKITranscript.JSONL.Line.header(
            .init(
                id: sessionId,
                timestamp: ISO8601DateFormatter().string(from: Date()),
                cwd: FileManager.default.currentDirectoryPath
            )
        )
        let encoder = makeJSONLEncoder()
        let data = try encoder.encode(header) + Data("\n".utf8)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
            if let size = attrs?[.size] as? NSNumber, size.intValue > 0 {
                return
            }
            try data.write(to: fileURL, options: .atomic)
            return
        }

        _ = STFolder(fileURL.deletingLastPathComponent()).createIfNotExists()
        try data.write(to: fileURL, options: .atomic)
    }

    public static func appendJSONLMessage(_ message: SKITranscript.JSONL.Message, sessionId: String, fileURL: URL) throws {
        try ensureJSONLHeader(sessionId: sessionId, fileURL: fileURL)
        let encoder = makeJSONLEncoder()
        let line = SKITranscript.JSONL.Line.message(message)
        let data = try encoder.encode(line) + Data("\n".utf8)

        let file = STFile(fileURL)
        let writer = try file.lineFile.newLineWriter
        try writer.append(data)
    }

    public static func loadJSONLMessages(fileURL: URL, maxReadBytes: Int) throws -> [SKITranscript.JSONL.Message] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }

        let text = try readTailUTF8(fileURL: fileURL, maxBytes: maxReadBytes)
        if text.isEmpty { return [] }

        let decoder = makeJSONLDecoder()
        let lines: [SKITranscript.JSONL.Line]
        do {
            lines = try JSONLines().decode(text, encoder: decoder)
        } catch {
            return []
        }

        return lines.compactMap { line in
            guard case .message(let message) = line else { return nil }
            return message
        }
    }

    private static func readTailUTF8(fileURL: URL, maxBytes: Int) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        let fileSize = try handle.seekToEnd()

        let startOffset: UInt64
        if maxBytes <= 0 {
            startOffset = 0
        } else if fileSize > UInt64(maxBytes) {
            startOffset = fileSize - UInt64(maxBytes)
        } else {
            startOffset = 0
        }

        try handle.seek(toOffset: startOffset)
        let data = try handle.readToEnd() ?? Data()
        try handle.close()

        var text = String(decoding: data, as: UTF8.self)
        if startOffset > 0 {
            if let idx = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: idx)...])
            } else {
                return ""
            }
        }
        return text
    }

    private static func makeJSONLEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static func makeJSONLDecoder() -> JSONDecoder {
        JSONDecoder()
    }
}
