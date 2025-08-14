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
    var isEnabled: Bool { get }
    func call(_ arguments: Arguments) async throws -> ToolOutput
}

public extension SKITool {
    
    var isEnabled: Bool { true }
    
    func call(_ instance: String) async throws -> String {
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
