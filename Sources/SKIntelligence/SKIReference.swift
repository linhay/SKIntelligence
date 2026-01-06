//
//  SKIReference.swift
//  SKIntelligence
//
//  Created by linhey on 1/6/26.
//

import Foundation

/// 引用链接，用于展示搜索结果、参考资料等外部链接
public struct SKIReference: Sendable, Codable, Hashable {
    /// 链接标题
    public let title: String
    /// 链接 URL
    public let url: String

    public init(title: String, url: String) {
        self.title = title
        self.url = url
    }
}
