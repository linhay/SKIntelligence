//
//  OpenAIClient.swift
//  SKIntelligence
//
//  Created by linhey on 6/14/25.
//

import Foundation
import SKIntelligence
import HTTPTypes
import HTTPTypesFoundation

public class OpenAIClient: SKILanguageModelClient {
    
    public enum EmbeddedURL: String {
        case openai   = "https://api.openai.com/v1/chat/completions"
        case deepseek = "https://api.deepseek.com/v1/chat/completions"
    }
    
    public enum EmbeddedModel: String {
        case deepseek_reasoner = "deepseek-reasoner"
        case deepseek_chat     = "deepseek-chat"
    }
    
    public var token: String = ""
    public var url: URL = URL(string: EmbeddedURL.openai.rawValue)!
    public var model: String = ""
    public var headerFields: HTTPFields = .init()
    
    public init() {}
    
    public func editRequestBody(_ body: inout ChatRequestBody) {
        body.model = model
        body.stream = false
    }
        
    public func respond(_ body: ChatRequestBody) async throws -> sending SKIResponse<ChatResponseBody> {
        let request = HTTPRequest(method: .post, url: url, headerFields: headerFields)
        let body = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.tools.upload(for: request, from: body)
        return try .init(httpResponse: response, data: data)
    }

}

public extension OpenAIClient {
    
    func url(_ value: String) throws -> OpenAIClient {
        if let url = URL(string: value) {
            self.url = url
        } else {
            throw URLError(.badURL)
        }
        return self
    }
    
    func url(_ value: EmbeddedURL) -> OpenAIClient {
        return try! url(value.rawValue)
    }
    
    func token(_ value: String) -> OpenAIClient {
        self.token = value
        headerFields[.contentType] = "application/json"
        headerFields[.authorization] = "Bearer \(token)"
        return self
    }
    
    func model(_ value: String) -> OpenAIClient {
        self.model = value
        return self
    }
    
    func model(_ value: EmbeddedModel) -> OpenAIClient {
        self.model = value.rawValue
        return self
    }
    
}
