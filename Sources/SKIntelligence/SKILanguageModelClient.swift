//
//  SKILanguageModelClient.swift
//  SKIntelligence
//
//  Created by linhey on 6/14/25.
//

import Foundation

public protocol SKILanguageModelClient {
    func editRequestBody(_ body: inout ChatRequestBody)
    func respond(_ body: ChatRequestBody) async throws -> sending SKIResponse<ChatResponseBody>
}

public extension SKILanguageModelClient {
    func respond(_ build: (_ body: inout ChatRequestBody) -> Void) async throws -> sending SKIResponse<ChatResponseBody> {
        var requestBody = ChatRequestBody(messages: [])
        build(&requestBody)
        return try await respond(requestBody)
    }
}
