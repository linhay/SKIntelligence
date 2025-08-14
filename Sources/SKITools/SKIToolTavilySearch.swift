//
//  File.swift
//  SKIntelligence
//
//  Created by linhey on 6/13/25.
//

import Foundation
import HTTPTypes
import HTTPTypesFoundation
import SKIntelligence
import JSONSchemaBuilder

/// TavilySearch 封装了 Tavily API 的搜索功能。
public struct SKIToolTavilySearch: SKITool {
   
    public var name: String = "tavily-search"
    public var description: String = "Tavily 搜索工具，提供基于 Tavily API 的搜索功能。"
    
    /// Tavily 搜索参数结构体。
    @Schemable
    public struct Arguments: Codable {
        /// 查询内容。
        public let query: String
        /// 搜索主题，可选：general, news, finance
        public let topic: Topic?
        /// 搜索深度，可选：basic, advanced
        public let search_depth: SearchDepth?
        /// 每个来源返回的内容片段数量。
        public let chunks_per_source: Int?
        /// 最大返回结果数量。
        public let max_results: Int?
        /// 是否包含答案内容。
        public let include_answer: Bool?
        /// 是否包含原始内容。
        public let include_raw_content: Bool?

        /// 搜索主题枚举。
        @Schemable
        public enum Topic: String, Codable {
            case general, news, finance
        }

        /// 搜索深度枚举。
        @Schemable
        public enum SearchDepth: String, Codable {
            case basic, advanced
        }
        
        /// Tavily 搜索参数初始化方法。
        /// - Parameters:
        ///   - query: 查询内容
        ///   - topic: 搜索主题
        ///   - search_depth: 搜索深度
        ///   - chunks_per_source: 每个来源片段数
        ///   - max_results: 最大结果数
        ///   - include_answer: 是否包含答案
        ///   - include_raw_content: 是否包含原始内容
        public init(query: String,
             topic: Topic? = nil,
             search_depth: SearchDepth? = nil,
             chunks_per_source: Int? = nil,
             max_results: Int? = nil,
             include_answer: Bool? = true,
             include_raw_content: Bool? = true) {
            self.query = query
            self.topic = topic
            self.search_depth = search_depth
            self.chunks_per_source = chunks_per_source
            self.max_results = max_results
            self.include_answer = include_answer
            self.include_raw_content = include_raw_content
        }
    }
    
    /// Tavily API 响应结构体。
    @Schemable
    public struct ToolOutput: Codable, Sendable {
        @SchemaOptions(.description("查询内容"))
        public let query: String
        /// Tavily 返回的答案（可选）。
        @SchemaOptions(.description("Tavily 返回的答案"))
        public let answer: String?
        /// 搜索结果数组。
        @SchemaOptions(.description("搜索结果数组"))
        public let results: [Result]
        
        /// 单条搜索结果。
        @Schemable
        public struct Result: Codable, Sendable {
            /// 结果标题。
            @SchemaOptions(.description("结果标题"))
            public let title: String
            /// 结果 URL。
            @SchemaOptions(.description("结果 URL"))
            public let url: String
            /// 结果内容片段（可选）。
            @SchemaOptions(.description("结果内容片段"))
            public let content: String?
        }
    }

    /// API 密钥。
    public var apiKey: String
    
    public init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    public func call(_ arguments: Arguments) async throws -> ToolOutput {
        // 1. 构造 URL 和 JSON 请求体
        let url = URL(string: "https://api.tavily.com/search")!
        let bodyData = try JSONEncoder().encode(arguments)

        // 2. 构造 HTTP 请求
        var request = HTTPRequest(
            method: .post,
            url: url
        )
        request.headerFields[.contentType] = "application/json"
        request.headerFields[.authorization] = "Bearer \(apiKey)"
        // 3. 发出请求
        let (responseBody, response) = try await URLSession.tools.upload(for: request, from: bodyData)
        // 4. 解析响应
        guard response.status.kind == .successful else {
            String(data: responseBody, encoding: .utf8).map { print("Response body: \($0)") }
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(ToolOutput.self, from: responseBody)
    }
}
