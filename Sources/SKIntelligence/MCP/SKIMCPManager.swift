//
//  SKIMCPManager.swift
//  SKIntelligence
//
//  Created by linhey on 6/14/25.
//

import Foundation
import MCP

//

/// Manages multiple MCP server connections.
public actor SKIMCPManager {

    /// Shared singleton instance.
    public static let shared = SKIMCPManager()

    private var clients: [String: SKIMCPClient] = [:]

    public init() {}

    /// Registers and connects to a new MCP server.
    /// - Parameters:
    ///   - id: Unique identifier for this server.
    ///   - endpoint: The SSE endpoint URL.
    ///   - headers: Optional headers.
    public func register(id: String, endpoint: URL, headers: [String: String]? = nil) async throws {
        // Disconnect existing if any
        if let existing = clients[id] {
            await existing.disconnect()
        }

        let client = SKIMCPClient(
            endpoint: endpoint, headers: headers, clientName: "SKIntelligence-\(id)")
        clients[id] = client

        // Connect automatically
        try await client.connect()
    }

    /// Unregisters and disconnects an MCP server.
    public func unregister(id: String) async {
        guard let client = clients[id] else { return }
        await client.disconnect()
        clients.removeValue(forKey: id)
    }

    /// Retrieves all tools from all registered MCP servers.
    public func getAllTools() async throws -> [SKIMCPTool] {
        var allTools: [SKIMCPTool] = []

        for (_, client) in clients {
            do {
                let mcpTools = try await client.listTools()
                let tools = mcpTools.map { SKIMCPTool(mcpTool: $0, client: client) }
                allTools.append(contentsOf: tools)
            } catch {
                print("Failed to list tools for client: \(error)")
                // Continue with other clients
            }
        }

        return allTools
    }

    /// Disconnects all clients.
    public func disconnectAll() async {
        for client in clients.values {
            await client.disconnect()
        }
        clients.removeAll()
    }
}
