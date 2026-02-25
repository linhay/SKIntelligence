//
//  File.swift
//  SKIntelligence
//
//  Created by linhey on 6/12/25.
//

import Foundation
import JSONSchema
import JSONSchemaBuilder

public struct SKIToolMetadata: Sendable, Equatable {
    public var name: String
    public var description: String
    public var shortDescription: String
    public var isEnabled: Bool
    public var parameters: [String: JSONValue]

    public init(
        name: String,
        description: String,
        shortDescription: String,
        isEnabled: Bool,
        parameters: [String: JSONValue]
    ) {
        self.name = name
        self.description = description
        self.shortDescription = shortDescription
        self.isEnabled = isEnabled
        self.parameters = parameters
    }
}

public protocol SKITool: Sendable {

    associatedtype ToolOutput: Codable
    associatedtype Arguments: Schemable where Arguments.Schema.Output == Arguments
    var name: String { get }
    var description: String { get }
    var shortDescription: String { get }
    var isEnabled: Bool { get }
    /// 根据参数生成用户友好的显示名称（支持异步数据库查询）
    /// - Parameter arguments: 工具参数
    /// - Returns: 包含参数上下文的显示名称，如 "查询 [白血病] 详情"
    func displayName(for arguments: Arguments) async -> String
    func call(_ arguments: Arguments) async throws -> ToolOutput
    /// 从工具输出中提取引用链接
    /// - Parameter output: 工具输出
    /// - Returns: 引用链接数组
    func references(from output: ToolOutput) -> [SKIReference]
}

extension SKITool {

    public var shortDescription: String { description }
    public var isEnabled: Bool { true }

    public func displayName(for arguments: String) async throws -> String {
        let arguments = try Self.arguments(from: arguments)
        return await displayName(for: arguments)
    }

    public func displayName(for arguments: Arguments) async -> String { name }

    public func references(from output: ToolOutput) -> [SKIReference] { [] }

    public static func arguments(from instance: String) throws -> Arguments {
        try Arguments.schema.parseAndValidate(instance: instance)
    }

    public func call(_ instance: String) async throws -> String {
        let arguments = try Arguments.schema.parseAndValidate(instance: instance)
        let out = try await self.call(arguments)
        let encode = try JSONEncoder().encode(out)
        let jsonString = String(data: encode, encoding: .utf8) ?? ""
        return jsonString
    }

    /// 从工具输出 JSON 字符串中提取引用链接
    public func references(from outputString: String) -> [SKIReference] {
        guard let data = outputString.data(using: .utf8),
            let output = try? JSONDecoder().decode(ToolOutput.self, from: data)
        else { return [] }
        return references(from: output)
    }

    public var metadata: SKIToolMetadata {
        .init(
            name: name,
            description: description,
            shortDescription: shortDescription,
            isEnabled: isEnabled,
            parameters: schemaParameters
        )
    }

}

extension SKITool {

    var schemaParameters: [String: JSONValue] {
        Arguments.schema.schemaValue.object ?? [:]
    }

}
