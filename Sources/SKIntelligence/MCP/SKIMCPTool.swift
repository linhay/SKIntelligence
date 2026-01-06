//
//  SKIMCPTool.swift
//  SKIntelligence
//
//  Created by linhey on 6/14/25.
//

import Foundation
import JSONSchema
import MCP
import STJSON

//

/// A wrapper for MCP Tool to be used within SKIntelligence.
public struct SKIMCPTool: Sendable {

    public let mcpTool: MCP.Tool
    private let client: SKIMCPClient

    public init(mcpTool: MCP.Tool, client: SKIMCPClient) {
        self.mcpTool = mcpTool
        self.client = client
    }

    public var name: String { mcpTool.name }
    public var description: String? { mcpTool.description }

    /// Converts the MCP tool definition to ChatRequestBody.Tool format.
    public var definition: ChatRequestBody.Tool {
        let parameters = convertSchema(mcpTool.inputSchema)
        return .function(
            name: name,
            description: description,
            parameters: parameters,
            strict: nil  // MCP doesn't strictly specify 'strict' mode in the same way, defaulting to nil (false/optional)
        )
    }

    /// Calls the tool with the given arguments.
    public func call(_ arguments: [String: Any]?) async throws -> String {
        return try await client.callTool(name: name, arguments: arguments)
    }

    // MARK: - Helper

    private func convertSchema(_ value: MCP.Value) -> [String: JSONValue]? {
        // Convert MCP.Value to JSONSchema.JSONValue via Data
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        do {
            let data = try encoder.encode(value)
            let jsonValue = try decoder.decode(JSONValue.self, from: data)

            if case .object(let dict) = jsonValue {
                return dict
            }
            return nil
        } catch {
            print("Failed to convert MCP schema: \(error)")
            return nil
        }
    }
}
