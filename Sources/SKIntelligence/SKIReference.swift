//
//  SKIReference.swift
//  SKIntelligence
//
//  Created by linhey on 1/6/26.
//

import Foundation

public struct SKIReferenceType: RawRepresentable, ExpressibleByStringLiteral, Sendable, Equatable,
    Codable, Hashable
{

    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

}

extension SKIReferenceType {

    public static let web = SKIReferenceType("web")
    public static let image = SKIReferenceType("image")

}

public struct SKIReferenceSource: RawRepresentable, ExpressibleByStringLiteral, Sendable, Equatable,
    Codable, Hashable
{

    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

}
extension SKIReferenceSource {

    public static let search = SKIReferenceSource("search")

}

/// 引用链接，用于展示搜索结果、参考资料等外部链接
public struct SKIReference: Sendable, Codable, Hashable, Equatable {
    /// 链接标题
    public let title: String
    /// 链接 URL
    public let url: String
    /// 引用类型，供外部标记使用（如 "web", "image", "document" 等）
    public var type: SKIReferenceType?
    /// 来源，标记引用来自 tools/其他来源
    public var source: SKIReferenceSource?

    public init(
        title: String,
        url: String,
        type: SKIReferenceType? = nil,
        source: SKIReferenceSource? = nil
    ) {
        self.title = title
        self.url = url
        self.type = type
        self.source = source
    }
}
