//
//  File.swift
//  SKIntelligence
//
//  Created by linhey on 6/12/25.
//

import Foundation
import JSONSchema
import JSONSchemaBuilder

public protocol SKITool {

    associatedtype ToolOutput: Encodable
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

}

extension SKITool {

    public var shortDescription: String { description }
    public var isEnabled: Bool { true }

    public func displayName(for arguments: String) async throws -> String {
        let arguments = try Self.arguments(from: arguments)
        return await displayName(for: arguments)
    }

    public func displayName(for arguments: Arguments) async -> String { name }

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

}

extension SKITool {

    var schemaParameters: [String: JSONValue] {
        Arguments.schema.schemaValue.object ?? [:]
    }

}
