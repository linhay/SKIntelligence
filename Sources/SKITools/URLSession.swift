//
//  File.swift
//  SKIntelligence
//
//  Created by linhey on 6/14/25.
//

import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

extension URLSession {

    public static let tools = {
        let config = URLSessionConfiguration.default
        return URLSession(configuration: config)
    }()

}

// MARK: - Cross-Platform Streaming Support

/// A cross-platform async sequence for streaming HTTP response data line by line.
public struct HTTPLineStream: AsyncSequence {
    public typealias Element = String

    private let request: URLRequest
    private let session: URLSession

    public init(request: URLRequest, session: URLSession = .tools) {
        self.request = request
        self.session = session
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(request: request, session: session)
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        private let request: URLRequest
        private let session: URLSession
        private var buffer: String = ""
        private var dataIterator: DataStreamIterator?
        private var isFinished = false

        init(request: URLRequest, session: URLSession) {
            self.request = request
            self.session = session
        }

        public mutating func next() async throws -> String? {
            if isFinished { return nil }

            // Initialize data iterator on first call
            if dataIterator == nil {
                dataIterator = try await DataStreamIterator(request: request, session: session)
            }

            // Try to get a complete line from buffer
            while true {
                if let newlineIndex = buffer.firstIndex(of: "\n") {
                    let line = String(buffer[..<newlineIndex])
                    buffer = String(buffer[buffer.index(after: newlineIndex)...])
                    return line
                }

                // Need more data
                guard let chunk = try await dataIterator?.next() else {
                    isFinished = true
                    // Return any remaining content
                    if !buffer.isEmpty {
                        let remaining = buffer
                        buffer = ""
                        return remaining
                    }
                    return nil
                }

                if let text = String(data: chunk, encoding: .utf8) {
                    buffer += text
                }
            }
        }
    }
}

/// Internal data stream iterator that works on both Apple and Linux platforms
private struct DataStreamIterator: AsyncIteratorProtocol {
    typealias Element = Data

    #if canImport(FoundationNetworking)
        // Linux implementation using callback-based approach
        private let dataAccumulator: LinuxDataAccumulator

        init(request: URLRequest, session: URLSession) async throws {
            self.dataAccumulator = LinuxDataAccumulator()
            self.dataAccumulator.start(request: request, session: session)
        }

        mutating func next() async throws -> Data? {
            return await dataAccumulator.nextChunk()
        }
    #else
        // Apple platform implementation using URLSession.bytes
        private var bytesIterator: URLSession.AsyncBytes.Iterator?
        private var currentBatch: Data = Data()
        private let batchSize = 1024  // Read in chunks for efficiency

        init(request: URLRequest, session: URLSession) async throws {
            let (bytes, response) = try await session.bytes(for: request)

            // Check HTTP status
            if let httpResponse = response as? HTTPURLResponse {
                let statusCode = httpResponse.statusCode
                if statusCode >= 400 {
                    if statusCode == 429 {
                        throw URLError(.userAuthenticationRequired)  // Rate limit
                    }
                    throw URLError(.badServerResponse)
                }
            }

            self.bytesIterator = bytes.makeAsyncIterator()
        }

        mutating func next() async throws -> Data? {
            guard var iterator = bytesIterator else { return nil }

            var chunk = Data()
            for _ in 0..<batchSize {
                guard let byte = try await iterator.next() else {
                    bytesIterator = iterator
                    return chunk.isEmpty ? nil : chunk
                }
                chunk.append(byte)
                // Return early on newline for line-based parsing
                if byte == UInt8(ascii: "\n") {
                    bytesIterator = iterator
                    return chunk
                }
            }

            bytesIterator = iterator
            return chunk.isEmpty ? nil : chunk
        }
    #endif
}

#if canImport(FoundationNetworking)
    /// Linux-specific data accumulator using URLSessionDataDelegate
    private final class LinuxDataAccumulator: NSObject, URLSessionDataDelegate {
        private var continuation: AsyncThrowingStream<Data, Error>.Continuation?
        private var stream: AsyncThrowingStream<Data, Error>?
        private var streamIterator: AsyncThrowingStream<Data, Error>.AsyncIterator?
        private var task: URLSessionDataTask?
        private let lock = NSLock()

        override init() {
            super.init()
        }

        func start(request: URLRequest, session: URLSession) {
            let (stream, continuation) = AsyncThrowingStream.makeStream(
                of: Data.self, throwing: Error.self)

            lock.lock()
            self.stream = stream
            self.continuation = continuation
            self.streamIterator = stream.makeAsyncIterator()
            lock.unlock()

            // Create a session with delegate
            let delegateSession = URLSession(
                configuration: session.configuration,
                delegate: self,
                delegateQueue: nil
            )

            task = delegateSession.dataTask(with: request)
            task?.resume()
        }

        func nextChunk() async -> Data? {
            do {
                lock.lock()
                var iterator = streamIterator
                lock.unlock()

                let result = try await iterator?.next()

                lock.lock()
                streamIterator = iterator
                lock.unlock()

                return result
            } catch {
                return nil
            }
        }

        // MARK: - URLSessionDataDelegate

        func urlSession(
            _ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data
        ) {
            lock.lock()
            continuation?.yield(data)
            lock.unlock()
        }

        func urlSession(
            _ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?
        ) {
            lock.lock()
            if let error = error {
                continuation?.finish(throwing: error)
            } else {
                continuation?.finish()
            }
            lock.unlock()
        }
    }
#endif

// MARK: - URLSession Extension for Streaming

extension URLSession {
    /// Creates a cross-platform line stream for the given request.
    /// Works on both Apple platforms (using URLSession.bytes) and Linux (using URLSessionDataDelegate).
    public func lineStream(for request: URLRequest) -> HTTPLineStream {
        HTTPLineStream(request: request, session: self)
    }
}
