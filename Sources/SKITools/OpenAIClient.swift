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

public struct OpenAIClient: SKILanguageModelClient {
    
    public let token: String
    public let url: URL
    public let model: String
    public var headerFields: HTTPFields = .init()
    
    public init(url: String, token: String, model: String) throws {
        self.token = token
        self.model = model
        
        if let url = URL(string: url) {
            self.url = url
        } else {
            throw URLError(.badURL)
        }
        headerFields[.contentType] = "application/json"
        headerFields[.authorization] = "Bearer \(token)"
    }
    
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
