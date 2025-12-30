//
//  File.swift
//  SKIntelligence
//
//  Created by linhey on 12/29/25.
//

import Foundation
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
