import Foundation
import XCTest
import Alamofire
import HTTPTypes
@testable import SKIClients
@testable import SKIntelligence

final class OpenAIClientFallbackEndpointTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testRespondFallsBackToSecondaryEndpointWhenPrimaryIsUnavailable() async throws {
        MockURLProtocol.handler = { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }
            if url.host == "primary.example.com" {
                let response = HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil)!
                return (response, Data("{\"error\":\"primary down\"}".utf8))
            }
            if url.host == "fallback.example.com" {
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(validChatResponseJSON(content: "fallback-ok").utf8))
            }
            throw URLError(.badServerResponse)
        }

        let client = makeClient()
        client.profiles([
            .init(
                url: URL(string: "https://primary.example.com/v1/chat/completions")!,
                token: "primary-token",
                model: "gpt-primary"
            ),
            .init(
                url: URL(string: "https://fallback.example.com/v1/chat/completions")!,
                token: "fallback-token",
                model: "gpt-fallback"
            )
        ])
        client.retry(.init(maxRetries: 1, baseDelay: 0, maxDelay: 0, useJitter: false))

        let response = try await client.respond(ChatRequestBody(messages: [.user(content: .text("hello"))]))
        XCTAssertEqual(response.content.choices.first?.message.content, "fallback-ok")

        let requestedHosts = MockURLProtocol.requestedURLs.compactMap(\.host)
        XCTAssertEqual(requestedHosts, ["primary.example.com", "fallback.example.com"])
    }

    func testRespondWithoutFallbackStillFailsOnPrimaryOutage() async throws {
        MockURLProtocol.handler = { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }
            let response = HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil)!
            return (response, Data("{\"error\":\"primary down\"}".utf8))
        }

        let client = makeClient()
        client.profiles([
            .init(
                url: URL(string: "https://primary.example.com/v1/chat/completions")!,
                token: "primary-token",
                model: "gpt-primary"
            )
        ])
        client.retry(.init(maxRetries: 0, baseDelay: 0, maxDelay: 0, useJitter: false))

        do {
            _ = try await client.respond(ChatRequestBody(messages: [.user(content: .text("hello"))]))
            XCTFail("Expected request to fail")
        } catch let error as SKIToolError {
            switch error {
            case .serverError(let statusCode, _):
                XCTAssertEqual(statusCode, 503)
            default:
                XCTFail("Unexpected SKIToolError: \(error)")
            }
        }
    }

    func testHeaderAuthorizationOverridesToken() async throws {
        MockURLProtocol.handler = { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let auth = request.value(forHTTPHeaderField: "Authorization")
            if auth == "Custom test-auth" {
                return (response, Data(validChatResponseJSON(content: "auth-ok").utf8))
            }
            return (response, Data("{\"error\":\"bad auth\"}".utf8))
        }

        var fields = HTTPFields()
        fields[.authorization] = "Custom test-auth"

        let client = makeClient()
        client.profiles([
            .init(
                url: URL(string: "https://auth.example.com/v1/chat/completions")!,
                token: "token-should-not-win",
                model: "gpt-auth",
                headerFields: fields
            )
        ])
        client.retry(.init(maxRetries: 0, baseDelay: 0, maxDelay: 0, useJitter: false))

        let response = try await client.respond(ChatRequestBody(messages: [.user(content: .text("hello"))]))
        XCTAssertEqual(response.content.choices.first?.message.content, "auth-ok")
    }

    func testEmptyProfilesThrowsInvalidArguments() async throws {
        let client = makeClient()
        client.profiles([])

        do {
            _ = try await client.respond(ChatRequestBody(messages: [.user(content: .text("hello"))]))
            XCTFail("Expected request to fail when profiles is empty")
        } catch let error as SKIToolError {
            switch error {
            case .invalidArguments(let message):
                XCTAssertTrue(message.contains("profiles is empty"))
            default:
                XCTFail("Unexpected SKIToolError: \(error)")
            }
        }
    }

    private func makeClient() -> OpenAIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = Session(configuration: configuration)
        return OpenAIClient(session: session)
    }
}

private final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    static var requestedURLs: [URL] = []

    static func reset() {
        handler = nil
        requestedURLs = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            if let url = request.url {
                Self.requestedURLs.append(url)
            }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func validChatResponseJSON(content: String) -> String {
    """
    {
      "choices": [
        {
          "finish_reason": "stop",
          "message": {
            "role": "assistant",
            "content": "\(content)"
          }
        }
      ],
      "created": 1,
      "model": "gpt-test"
    }
    """
}
