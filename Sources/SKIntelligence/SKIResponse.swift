//
//  SKIResponse.swift
//  SKIntelligence
//
//  Created by linhey on 6/13/25.
//

import Foundation
import HTTPTypes
import HTTPTypesFoundation

public struct SKIResponse<Content: Decodable> {
    
    public var httpResponse: HTTPResponse
    public var content: Content
    
    public init(httpResponse: HTTPResponse, data: Data) throws {
        self.httpResponse = httpResponse
        self.content = try JSONDecoder().decode(Content.self, from: data)
    }
    
}
