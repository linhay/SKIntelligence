//
//  ServerEventParser.swift
//  SKIntelligence
//
//  Created by linhey on 1/5/26.
//

import Foundation

/// A parser for Server-Sent Events (SSE) protocol.
///
/// SSE format:
/// ```
/// event: message
/// data: {"content": "Hello"}
/// id: 123
///
/// data: {"content": "World"}
///
/// data: [DONE]
/// ```
public struct ServerEventParser: Sendable {

    /// A parsed SSE event
    public struct Event: Sendable, Equatable {
        public let id: String?
        public let event: String?
        public let data: String?
        public let retry: Int?

        public init(id: String? = nil, event: String? = nil, data: String? = nil, retry: Int? = nil)
        {
            self.id = id
            self.event = event
            self.data = data
            self.retry = retry
        }

        /// Whether this is the terminal [DONE] signal
        public var isDone: Bool {
            data?.trimmingCharacters(in: .whitespaces) == "[DONE]"
        }
    }

    // Line feed and carriage return bytes
    private static let lf: UInt8 = 0x0A  // \n
    private static let cr: UInt8 = 0x0D  // \r
    private static let colon: UInt8 = 0x3A  // :

    private var buffer: Data = Data()

    public init() {}

    /// Parse incoming data and return complete events.
    ///
    /// Buffers incomplete data across multiple calls.
    /// - Parameter data: New data chunk from network
    /// - Returns: Array of complete events parsed from buffer
    public mutating func parse(_ data: Data) -> [Event] {
        buffer.append(data)

        let (completeMessages, remainingData) = splitBuffer()
        buffer = remainingData

        return completeMessages.compactMap { parseEvent(from: $0) }
    }

    /// Reset the parser state
    public mutating func reset() {
        buffer = Data()
    }

    // MARK: - Private

    /// Split buffer into complete messages (separated by double newlines) and remaining incomplete data
    private func splitBuffer() -> (complete: [Data], remaining: Data) {
        // SSE messages are separated by \n\n or \r\n\r\n
        let separators: [[UInt8]] = [
            [Self.lf, Self.lf],
            [Self.cr, Self.lf, Self.cr, Self.lf],
        ]

        // Find the last separator to determine where complete messages end
        var lastSeparatorEnd: Data.Index?
        var chosenSeparator: [UInt8]?

        for separator in separators {
            if let range = buffer.lastRange(of: Data(separator)) {
                if lastSeparatorEnd == nil || range.upperBound > lastSeparatorEnd! {
                    lastSeparatorEnd = range.upperBound
                    chosenSeparator = separator
                }
            }
        }

        guard let separatorEnd = lastSeparatorEnd, let separator = chosenSeparator else {
            // No complete messages yet
            return ([], buffer)
        }

        // Split complete portion into individual messages
        let completeData = buffer[buffer.startIndex..<separatorEnd]
        let remainingData = buffer[separatorEnd..<buffer.endIndex]

        let messages = completeData.split(separator: Data(separator))
        let cleanedMessages = messages.map { cleanMessageData($0) }

        return (cleanedMessages, Data(remainingData))
    }

    /// Clean trailing CR/LF from message data
    private func cleanMessageData(_ data: Data) -> Data {
        var clean = data
        while !clean.isEmpty && (clean.last == Self.cr || clean.last == Self.lf) {
            clean = clean.dropLast()
        }
        return Data(clean)
    }

    /// Parse a complete message into an Event
    private func parseEvent(from data: Data) -> Event? {
        guard let text = String(data: data, encoding: .utf8) else {
            return nil
        }

        var id: String?
        var event: String?
        var dataLines: [String] = []
        var retry: Int?

        // Parse each line
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for line in lines {
            let lineStr = String(line)

            // Skip comment lines (starting with :)
            if lineStr.hasPrefix(":") {
                continue
            }

            // Parse field: value
            if let colonIndex = lineStr.firstIndex(of: ":") {
                let field = String(lineStr[..<colonIndex])
                var value = String(lineStr[lineStr.index(after: colonIndex)...])

                // Remove leading space if present (as per SSE spec)
                if value.hasPrefix(" ") {
                    value.removeFirst()
                }

                switch field {
                case "id":
                    id = value
                case "event":
                    event = value
                case "data":
                    dataLines.append(value)
                case "retry":
                    retry = Int(value)
                default:
                    break
                }
            } else if !lineStr.isEmpty {
                // Field with no value
                switch lineStr {
                case "data":
                    dataLines.append("")
                default:
                    break
                }
            }
        }

        // Join multiple data lines with newline (as per SSE spec)
        let joinedData = dataLines.isEmpty ? nil : dataLines.joined(separator: "\n")

        // Only return event if we have at least some data
        guard id != nil || event != nil || joinedData != nil || retry != nil else {
            return nil
        }

        return Event(id: id, event: event, data: joinedData, retry: retry)
    }
}

// MARK: - Data Extension for Split

extension Data {
    fileprivate func split(separator: Data) -> [Data] {
        var result: [Data] = []
        var searchStart = startIndex

        while searchStart < endIndex {
            if let range = self[searchStart...].range(of: separator) {
                result.append(Data(self[searchStart..<range.lowerBound]))
                searchStart = range.upperBound
            } else {
                result.append(Data(self[searchStart...]))
                break
            }
        }

        return result
    }

    fileprivate func lastRange(of data: Data) -> Range<Data.Index>? {
        var lastFound: Range<Data.Index>?
        var searchStart = startIndex

        while searchStart < endIndex {
            if let range = self[searchStart...].range(of: data) {
                lastFound = range
                searchStart = range.upperBound
            } else {
                break
            }
        }

        return lastFound
    }
}
