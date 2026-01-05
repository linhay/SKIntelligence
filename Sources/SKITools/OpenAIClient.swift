//
//  OpenAIClient.swift
//  SKIntelligence
//
//  Created by linhey on 6/14/25.
//

import Foundation
import HTTPTypes
import HTTPTypesFoundation
import SKIntelligence

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

// MARK: - Retry Configuration

/// Configuration for retry behavior with exponential backoff.
public struct RetryConfiguration: Sendable {
    /// Maximum number of retry attempts (not including the initial attempt)
    public var maxRetries: Int

    /// Base delay for exponential backoff (in seconds)
    public var baseDelay: TimeInterval

    /// Maximum delay between retries (in seconds)
    public var maxDelay: TimeInterval

    /// HTTP status codes that should trigger a retry
    public var retryableStatusCodes: Set<Int>

    /// Whether to use jitter to randomize delays
    public var useJitter: Bool

    /// Default retry configuration
    public static let `default` = RetryConfiguration(
        maxRetries: 3,
        baseDelay: 1.0,
        maxDelay: 20.0,
        retryableStatusCodes: [429, 500, 502, 503, 504],
        useJitter: true
    )

    /// No retry configuration
    public static let none = RetryConfiguration(
        maxRetries: 0,
        baseDelay: 0,
        maxDelay: 0,
        retryableStatusCodes: [],
        useJitter: false
    )

    public init(
        maxRetries: Int = 3,
        baseDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 20.0,
        retryableStatusCodes: Set<Int> = [429, 500, 502, 503, 504],
        useJitter: Bool = true
    ) {
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.retryableStatusCodes = retryableStatusCodes
        self.useJitter = useJitter
    }

    /// Calculates delay for the given attempt using exponential backoff with optional jitter.
    /// Based on AWS/Google Cloud "full jitter" algorithm.
    func delay(forAttempt attempt: Int) -> TimeInterval {
        // Exponential: baseDelay * 2^attempt
        let exponentialDelay = baseDelay * pow(2.0, Double(attempt))
        let cappedDelay = min(exponentialDelay, maxDelay)

        if useJitter {
            // Full jitter: random value between 0 and cappedDelay
            return Double.random(in: 0...cappedDelay)
        }
        return cappedDelay
    }
}

// MARK: - OpenAI Client

public class OpenAIClient: SKILanguageModelClient {

    public enum EmbeddedURL: String {
        case dashscope = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
        case openai = "https://api.openai.com/v1/chat/completions"
        case deepseek = "https://api.deepseek.com/v1/chat/completions"
        case moonshot = "https://api.moonshot.cn/v1/chat/completions"
        /// https://openrouter.ai/docs/quickstart
        case openrouter = "https://openrouter.ai/api/v1/chat/completions"
        /// https://aistudio.google.com/apikey
        case gemini = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
    }

    public enum EmbeddedModel: String {
        case deepseek_reasoner = "deepseek-reasoner"
        case deepseek_chat = "deepseek-chat"
        case gemini_2_5_pro = "gemini-2.5-pro"
        case gemini_2_5_flash = "gemini-2.5-flash"
        case gemini_2_5_flash_lite = "gemini-2.5-flash-lite"
    }

    // MARK: - Properties

    public var token: String = ""
    public var url: URL = URL(string: EmbeddedURL.openai.rawValue)!
    public var model: String = ""
    public var headerFields: HTTPFields = .init()
    public var session: URLSession

    /// Request timeout in seconds (nil means no timeout)
    public var timeoutInterval: TimeInterval? = nil

    /// Retry configuration
    public var retryConfiguration: RetryConfiguration = .default

    // MARK: - Initialization

    public init(session: URLSession = .tools) {
        self.session = session
    }

    // MARK: - SKILanguageModelClient

    public func respond(_ body: ChatRequestBody) async throws
        -> sending SKIResponse<ChatResponseBody>
    {
        var lastError: Error?
        var body = body
        body.model = model
        body.stream = false

        for attempt in 0...retryConfiguration.maxRetries {
            do {
                try Task.checkCancellation()
                return try await performRequest(body)
            } catch {
                lastError = error

                // Check if we should retry
                if attempt < retryConfiguration.maxRetries && shouldRetry(error: error) {
                    let delay = retryConfiguration.delay(forAttempt: attempt)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }

                throw error
            }
        }

        // Should not reach here, but just in case
        throw lastError
            ?? SKIToolError.retryExhausted(
                attempts: retryConfiguration.maxRetries + 1, lastError: URLError(.unknown))
    }

    // MARK: - Private Methods

    private func performRequest(_ body: ChatRequestBody) async throws -> SKIResponse<
        ChatResponseBody
    > {
        let request = HTTPRequest(method: .post, url: url, headerFields: headerFields)
        let bodyData = try JSONEncoder().encode(body)

        // Create a task with optional timeout
        return try await withThrowingTaskGroup(of: SKIResponse<ChatResponseBody>.self) { group in
            group.addTask {
                let (data, response) = try await self.session.upload(for: request, from: bodyData)

                // Check for HTTP errors
                let statusCode = response.status.code
                if statusCode >= 400 {
                    let message = String(data: data, encoding: .utf8)
                    if statusCode == 429 {
                        throw SKIToolError.rateLimitExceeded(retryAfter: nil)
                    }
                    throw SKIToolError.serverError(statusCode: Int(statusCode), message: message)
                }

                return try .init(httpResponse: response, data: data)
            }

            // Only add timeout task if timeoutInterval is set
            if let timeout = self.timeoutInterval {
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    throw SKIToolError.timeout(timeout)
                }
            }

            // Return the first completed task, cancel the other
            guard let result = try await group.next() else {
                throw SKIToolError.networkUnavailable
            }
            group.cancelAll()
            return result
        }
    }

    private func shouldRetry(error: Error) -> Bool {
        if let skiError = error as? SKIToolError {
            return skiError.isRetryable
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet:
                return true
            default:
                return false
            }
        }

        return false
    }

    // MARK: - Streaming

    public func streamingRespond(_ body: ChatRequestBody) async throws -> SKIResponseStream {
        var body = body
        body.model = model
        body.stream = true

        let bodyData = try JSONEncoder().encode(body)

        // Build URLRequest for streaming
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        for field in headerFields {
            urlRequest.setValue(field.value, forHTTPHeaderField: field.name.rawName)
        }
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.httpBody = bodyData

        if let timeout = timeoutInterval {
            urlRequest.timeoutInterval = timeout
        }

        // Capture session for the stream closure
        let session = self.session

        return SKIResponseStream { [urlRequest] in
            AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        var parser = ServerEventParser()
                        let decoder = JSONDecoder()

                        // Use cross-platform HTTPLineStream
                        let lineStream = session.lineStream(for: urlRequest)

                        for try await line in lineStream {
                            try Task.checkCancellation()

                            guard let lineData = (line + "\n\n").data(using: .utf8) else {
                                continue
                            }

                            let events = parser.parse(lineData)

                            for event in events {
                                // Skip [DONE] signal
                                if event.isDone {
                                    continuation.finish()
                                    return
                                }

                                guard let dataString = event.data,
                                    let jsonData = dataString.data(using: .utf8)
                                else {
                                    continue
                                }

                                do {
                                    let chunk = try decoder.decode(
                                        ChatStreamResponseChunk.self, from: jsonData)

                                    for choice in chunk.choices {
                                        // Yield raw chunks (including tool call deltas)
                                        let responseChunk = SKIResponseChunk(from: choice)
                                        continuation.yield(responseChunk)
                                    }
                                } catch {
                                    // Skip malformed JSON chunks
                                    continue
                                }
                            }
                        }

                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }

                continuation.onTermination = { @Sendable _ in
                    task.cancel()
                }
            }
        }

    }
}

// MARK: - Builder Pattern

extension OpenAIClient {

    public func url(_ value: String) throws -> OpenAIClient {
        if let url = URL(string: value) {
            self.url = url
        } else {
            throw URLError(.badURL)
        }
        return self
    }

    public func url(_ value: EmbeddedURL) -> OpenAIClient {
        return try! url(value.rawValue)
    }

    public func token(_ value: String) -> OpenAIClient {
        self.token = value
        headerFields[.contentType] = "application/json"
        headerFields[.authorization] = "Bearer \(token)"
        return self
    }

    public func model(_ value: String) -> OpenAIClient {
        self.model = value
        return self
    }

    public func model(_ value: EmbeddedModel) -> OpenAIClient {
        self.model = value.rawValue
        return self
    }

    public func timeout(_ interval: TimeInterval) -> OpenAIClient {
        self.timeoutInterval = interval
        return self
    }

    public func retry(_ configuration: RetryConfiguration) -> OpenAIClient {
        self.retryConfiguration = configuration
        return self
    }
}
