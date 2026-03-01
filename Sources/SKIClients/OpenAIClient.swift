//
//  OpenAIClient.swift
//  SKIntelligence
//
//  Created by linhey on 6/14/25.
//

import Alamofire
import EventSource
import Foundation
import HTTPTypes
import SKIntelligence

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

public class OpenAIClient: SKILanguageModelClient, Sendable {

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

    public struct EndpointProfile: Sendable {
        public var url: URL
        public var token: String?
        public var model: String
        public var headerFields: HTTPFields

        public init(
            url: URL,
            token: String? = nil,
            model: String,
            headerFields: HTTPFields = .init()
        ) {
            self.url = url
            self.token = token
            self.model = model
            self.headerFields = headerFields
        }
    }

    // MARK: - Properties

    public var profiles: [EndpointProfile] = [
        .init(url: URL(string: EmbeddedURL.openai.rawValue)!, token: nil, model: "")
    ]

    @available(*, deprecated, message: "Use profiles[0].token")
    public var token: String {
        get { profiles.first?.token ?? "" }
        set { ensureFirstProfile(); profiles[0].token = newValue }
    }

    @available(*, deprecated, message: "Use profiles[0].url")
    public var url: URL {
        get { profiles.first?.url ?? URL(string: EmbeddedURL.openai.rawValue)! }
        set { ensureFirstProfile(); profiles[0].url = newValue }
    }

    @available(*, deprecated, message: "Use profiles[0].model")
    public var model: String {
        get { profiles.first?.model ?? "" }
        set { ensureFirstProfile(); profiles[0].model = newValue }
    }

    @available(*, deprecated, message: "Use profiles[0].headerFields")
    public var headerFields: HTTPFields {
        get { profiles.first?.headerFields ?? .init() }
        set { ensureFirstProfile(); profiles[0].headerFields = newValue }
    }
    public var session: Session

    /// Request timeout in seconds (default: 600 seconds / 10 minutes)
    public var timeoutInterval: TimeInterval? = 600

    /// Maximum concurrent connections per host (default: 6)
    public var maxConcurrentConnectionsPerHost: Int = 6

    /// Retry configuration
    public var retryConfiguration: RetryConfiguration = .default

    // MARK: - Initialization

    public init(session: Session? = nil) {
        if let session = session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 600
            configuration.timeoutIntervalForResource = 600
            configuration.httpMaximumConnectionsPerHost = 8
            self.session = Session(configuration: configuration)
        }
    }

    // MARK: - SKILanguageModelClient

    public func respond(_ body: ChatRequestBody) async throws
        -> sending SKIResponse<ChatResponseBody>
    {
        var lastError: Error?
        let candidateProfiles = try configuredProfiles()
        let totalAttempts = max(retryConfiguration.maxRetries + 1, candidateProfiles.count)

        for attempt in 0..<totalAttempts {
            do {
                try Task.checkCancellation()
                let profile = candidateProfiles[attempt % candidateProfiles.count]
                var requestBody = body
                requestBody.model = profile.model
                requestBody.stream = false
                return try await performRequest(requestBody, profile: profile)
            } catch {
                lastError = error

                // Check if we should retry
                let hasNextAttempt = attempt < (totalAttempts - 1)
                if hasNextAttempt && shouldRetry(error: error) {
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

    private func performRequest(_ body: ChatRequestBody, profile: EndpointProfile) async throws -> SKIResponse<
        ChatResponseBody
    > {
        let bodyData = try JSONEncoder().encode(body)
        let httpHeaders = buildHTTPHeaders(profile: profile)

        let request = session.request(
            profile.url,
            method: .post,
            headers: httpHeaders
        ) { urlRequest in
            urlRequest.httpBody = bodyData
            if let timeout = self.timeoutInterval {
                urlRequest.timeoutInterval = timeout
            }
        }

        let response = await request.serializingData().response

        // Check for errors
        if let error = response.error {
            throw error
        }

        guard let data = response.data else {
            throw SKIToolError.networkUnavailable
        }

        // Check for HTTP errors
        if let statusCode = response.response?.statusCode, statusCode >= 400 {
            let message = String(data: data, encoding: .utf8)
            if statusCode == 429 {
                throw SKIToolError.rateLimitExceeded(retryAfter: nil)
            }
            throw SKIToolError.serverError(statusCode: statusCode, message: message)
        }

        let httpResponse = HTTPResponse(status: .init(code: response.response?.statusCode ?? 200))
        do {
            return try SKIResponse<ChatResponseBody>(httpResponse: httpResponse, data: data)
        } catch let decodingError as DecodingError {
            throw Self.enrichDecodingError(
                decodingError,
                data: data,
                model: profile.model,
                url: profile.url
            )
        }
    }

    private func shouldRetry(error: Error) -> Bool {
        if let skiError = error as? SKIToolError {
            return skiError.isRetryable
        }

        if let afError = error as? AFError {
            if case .sessionTaskFailed(let underlyingError) = afError,
                let urlError = underlyingError as? URLError
            {
                switch urlError.code {
                case .timedOut, .networkConnectionLost, .notConnectedToInternet:
                    return true
                default:
                    return false
                }
            }
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

    static func enrichDecodingError(
        _ error: DecodingError,
        data: Data,
        model: String,
        url: URL,
        snippetLimit: Int = 1024
    ) -> DecodingError {
        let (codingPath, reason, underlyingError) = decodingErrorContext(error)
        let snippet = redactedSnippet(from: data, limit: snippetLimit)
        let debugDescription =
            "\(reason); model=\(model); url=\(url.absoluteString); responseSnippet=\(snippet)"
        let context = DecodingError.Context(
            codingPath: codingPath,
            debugDescription: debugDescription,
            underlyingError: underlyingError
        )

        switch error {
        case .typeMismatch(let type, _):
            return .typeMismatch(type, context)
        case .valueNotFound(let type, _):
            return .valueNotFound(type, context)
        case .keyNotFound(let key, _):
            return .keyNotFound(key, context)
        case .dataCorrupted:
            return .dataCorrupted(context)
        @unknown default:
            return .dataCorrupted(context)
        }
    }

    private static func decodingErrorContext(_ error: DecodingError) -> (
        codingPath: [CodingKey], reason: String, underlyingError: Error?
    ) {
        switch error {
        case .typeMismatch(let type, let context):
            return (
                context.codingPath,
                "typeMismatch(\(type)): \(context.debugDescription)",
                context.underlyingError
            )
        case .valueNotFound(let type, let context):
            return (
                context.codingPath,
                "valueNotFound(\(type)): \(context.debugDescription)",
                context.underlyingError
            )
        case .keyNotFound(let key, let context):
            return (
                context.codingPath,
                "keyNotFound(\(key.stringValue)): \(context.debugDescription)",
                context.underlyingError
            )
        case .dataCorrupted(let context):
            return (
                context.codingPath,
                "dataCorrupted: \(context.debugDescription)",
                context.underlyingError
            )
        @unknown default:
            return ([], "unknown decoding error", nil)
        }
    }

    private static func redactedSnippet(from data: Data, limit: Int) -> String {
        let prefix = data.prefix(limit)
        let text = String(data: prefix, encoding: .utf8) ?? "<non-utf8>"
        return redactSensitiveFields(in: text)
    }

    private static func redactSensitiveFields(in text: String) -> String {
        let patterns = [
            #"(?i)("authorization"\s*:\s*")[^"]*(")"#,
            #"(?i)("api[_-]?key"\s*:\s*")[^"]*(")"#,
            #"(?i)("token"\s*:\s*")[^"]*(")"#
        ]

        var output = text
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(output.startIndex..<output.endIndex, in: output)
                output = regex.stringByReplacingMatches(
                    in: output,
                    options: [],
                    range: range,
                    withTemplate: "$1***$2"
                )
            }
        }
        return output
    }

    // MARK: - Streaming

    public func streamingRespond(_ body: ChatRequestBody) async throws -> SKIResponseStream {
        let candidateProfiles = try configuredProfiles()

        return SKIResponseStream {
            AsyncThrowingStream { continuation in
                Task { [self] in
                    var lastError: Error?
                    for (index, profile) in candidateProfiles.enumerated() {
                        var requestBody = body
                        requestBody.model = profile.model
                        requestBody.stream = true
                        var receivedAnyChunk = false
                        do {
                            let stream = try self.makeRawStreamChunkStream(
                                body: requestBody,
                                profile: profile
                            )
                            for try await chunk in stream {
                                receivedAnyChunk = true
                                if chunk.choices.isEmpty, let usage = chunk.usage {
                                    continuation.yield(SKIResponseChunk(usage: usage))
                                }
                                for choice in chunk.choices {
                                    continuation.yield(SKIResponseChunk(from: choice, usage: chunk.usage))
                                }
                            }
                            continuation.finish()
                            return
                        } catch {
                            lastError = error
                            let hasNextProfile = index + 1 < candidateProfiles.count
                            if hasNextProfile && !receivedAnyChunk && self.shouldRetry(error: error) {
                                continue
                            }
                            continuation.finish(throwing: error)
                            return
                        }
                    }
                    continuation.finish(
                        throwing: lastError
                            ?? SKIToolError.invalidArguments("OpenAIClient.profiles is empty")
                    )
                }
            }
        }
    }

    private func configuredProfiles() throws -> [EndpointProfile] {
        if profiles.isEmpty {
            throw SKIToolError.invalidArguments("OpenAIClient.profiles is empty")
        }
        return profiles
    }

    private func ensureFirstProfile() {
        if profiles.isEmpty {
            profiles = [
                .init(
                    url: URL(string: EmbeddedURL.openai.rawValue)!,
                    token: nil,
                    model: ""
                )
            ]
        }
    }

    private func buildHTTPHeaders(profile: EndpointProfile) -> HTTPHeaders {
        var fields = profile.headerFields
        if fields[.authorization] == nil, let token = profile.token, !token.isEmpty {
            fields[.authorization] = "Bearer \(token)"
        }
        if fields[.contentType] == nil {
            fields[.contentType] = "application/json"
        }

        var headers = HTTPHeaders()
        for field in fields {
            headers.add(name: field.name.rawName, value: field.value)
        }
        return headers
    }

    private func makeStreamingRequest(profile: EndpointProfile, bodyData: Data) -> URLRequest {
        var request = URLRequest(url: profile.url)
        request.httpMethod = "POST"
        request.httpBody = bodyData

        for field in profile.headerFields {
            request.setValue(field.value, forHTTPHeaderField: field.name.rawName)
        }
        if request.value(forHTTPHeaderField: "Authorization") == nil,
            let token = profile.token,
            !token.isEmpty
        {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        if let timeout = timeoutInterval {
            request.timeoutInterval = timeout
        }

        return request
    }

    private func makeRawStreamChunkStream(
        body: ChatRequestBody,
        profile: EndpointProfile
    ) throws -> AsyncThrowingStream<ChatStreamResponseChunk, Error> {
        let bodyData = try JSONEncoder().encode(body)
        let request = makeStreamingRequest(profile: profile, bodyData: bodyData)

        return AsyncThrowingStream { continuation in
            let decoder = JSONDecoder()
            let eventSource = EventSource(request: request)

            eventSource.onOpen = { @Sendable in
                // Connection opened
            }

            eventSource.onError = { @Sendable error in
                if let error {
                    continuation.finish(throwing: error)
                }
            }

            eventSource.onMessage = { @Sendable event in
                if event.data == "[DONE]" {
                    Task {
                        await eventSource.close()
                    }
                    continuation.finish()
                    return
                }

                guard let jsonData = event.data.data(using: .utf8),
                    let chunk = try? decoder.decode(ChatStreamResponseChunk.self, from: jsonData)
                else {
                    return
                }
                continuation.yield(chunk)
            }

            continuation.onTermination = { @Sendable _ in
                Task {
                    await eventSource.close()
                }
            }
        }
    }
}

// MARK: - Builder Pattern

extension OpenAIClient {

    public func profiles(_ values: [EndpointProfile]) -> OpenAIClient {
        self.profiles = values
        return self
    }

    public func addProfile(_ value: EndpointProfile) -> OpenAIClient {
        profiles.append(value)
        return self
    }

    @available(*, deprecated, message: "Use profiles(_:) / addProfile(_:)")
    public func url(_ value: String) throws -> OpenAIClient {
        if let url = URL(string: value) {
            ensureFirstProfile()
            profiles[0].url = url
        } else {
            throw URLError(.badURL)
        }
        return self
    }

    @available(*, deprecated, message: "Use profiles(_:) / addProfile(_:)")
    public func url(_ value: EmbeddedURL) -> OpenAIClient {
        return try! url(value.rawValue)
    }

    @available(*, deprecated, message: "Use profiles(_:) / addProfile(_:)")
    public func fallbackURLs(_ values: [URL]) -> OpenAIClient {
        ensureFirstProfile()
        let first = profiles[0]
        let mapped = values.map {
            EndpointProfile(
                url: $0,
                token: first.token,
                model: first.model,
                headerFields: first.headerFields
            )
        }
        profiles = [first] + mapped
        return self
    }

    @available(*, deprecated, message: "Use profiles(_:) / addProfile(_:)")
    public func fallbackURLs(_ values: [String]) throws -> OpenAIClient {
        let urls = try values.map { value -> URL in
            guard let url = URL(string: value) else {
                throw URLError(.badURL)
            }
            return url
        }
        return fallbackURLs(urls)
    }

    @available(*, deprecated, message: "Use profiles(_:) / addProfile(_:)")
    public func addFallbackURL(_ value: URL) -> OpenAIClient {
        return fallbackURLs((profiles.dropFirst().map(\.url)) + [value])
    }

    @available(*, deprecated, message: "Use profiles(_:) / addProfile(_:)")
    public func token(_ value: String) -> OpenAIClient {
        ensureFirstProfile()
        profiles[0].token = value
        return self
    }

    @available(*, deprecated, message: "Use profiles(_:) / addProfile(_:)")
    public func model(_ value: String) -> OpenAIClient {
        ensureFirstProfile()
        profiles[0].model = value
        return self
    }

    @available(*, deprecated, message: "Use profiles(_:) / addProfile(_:)")
    public func model(_ value: EmbeddedModel) -> OpenAIClient {
        ensureFirstProfile()
        profiles[0].model = value.rawValue
        return self
    }

    public func timeout(_ interval: TimeInterval) -> OpenAIClient {
        self.timeoutInterval = interval
        
        // Always update session configuration
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = interval
        configuration.timeoutIntervalForResource = interval
        configuration.httpMaximumConnectionsPerHost = maxConcurrentConnectionsPerHost
        self.session = Session(configuration: configuration)
        
        return self
    }

    public func retry(_ configuration: RetryConfiguration) -> OpenAIClient {
        self.retryConfiguration = configuration
        return self
    }

    public func maxConcurrentConnections(_ count: Int) -> OpenAIClient {
        self.maxConcurrentConnectionsPerHost = count
        
        // Always update session configuration
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeoutInterval ?? 600
        configuration.timeoutIntervalForResource = timeoutInterval ?? 600
        configuration.httpMaximumConnectionsPerHost = count
        self.session = Session(configuration: configuration)
        
        return self
    }

    public func session(_ value: Session) -> OpenAIClient {
        self.session = value
        return self
    }
}
