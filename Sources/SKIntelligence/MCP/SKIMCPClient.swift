//
//  SKIMCPClient.swift
//  SKIntelligence
//
//  Created by linhey on 6/14/25.
//

import Foundation
import MCP

//

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// A wrapper around MCP.Client to manage the connection and providing a cleaner interface for SKIntelligence.
public actor SKIMCPClient {

    // MARK: - Properties

    private let client: MCP.Client
    private let transport: any Transport

    /// The endpoint URL of the MCP server (SSE endpoint)
    public let endpoint: URL

    /// Custom headers for the connection
    public let headers: [String: String]?

    // MARK: - Initialization

    /// Initializes a new MCP client wrapper.
    /// - Parameters:
    ///   - endpoint: The URL of the MCP server (must be an SSE endpoint).
    ///   - headers: Optional headers to send with the connection request.
    ///   - clientName: Name of this client (sent to server).
    ///   - clientVersion: Version of this client (sent to server).
    public init(
        endpoint: URL,
        headers: [String: String]? = nil,
        clientName: String = "SKIntelligence",
        clientVersion: String = "1.0.0"
    ) {
        self.endpoint = endpoint
        self.headers = headers
        self.client = MCP.Client(name: clientName, version: clientVersion)

        // Initialize the transport
        // Use requestModifier to inject headers
        self.transport = HTTPClientTransport(
            endpoint: endpoint,
            requestModifier: { request in
                var req = request
                headers?.forEach { req.addValue($1, forHTTPHeaderField: $0) }
                return req
            }
        )
    }

    // MARK: - Connection Management

    /// Connects to the MCP server.
    public func connect() async throws {
        try await client.connect(transport: transport)
    }

    /// Disconnects from the MCP server.
    public func disconnect() async {
        await client.disconnect()
    }

    // MARK: - Tool Operations

    /// Lists all available tools from the connected MCP server.
    public func listTools() async throws -> [MCP.Tool] {
        let result = try await client.listTools()
        return result.tools
    }

    /// Calls a specific tool on the MCP server.
    /// - Parameters:
    ///   - name: The name of the tool to call.
    ///   - arguments: The arguments to pass to the tool.
    /// - Returns: The result of the tool execution as a string (usually JSON).
    public func callTool(name: String, arguments: [String: Any]?) async throws -> String {
        // Convert arguments to [String: Value]
        // Note: SKIntelligence usually handles args as JSON string or codable.
        // We need to map [String: Any] to [String: Value] where Value is MCP's JSON value type.

        var mcpArgs: [String: Value]? = nil
        if let arguments = arguments {
            mcpArgs = try arguments.mapValues { try Value(from: $0) }
        }

        let result = try await client.callTool(name: name, arguments: mcpArgs)

        // Combine all content parts into a single response string
        // MCP Tool.Content can be text or image. simplified here to just text parts or description.
        let textContent = result.content.compactMap { content -> String? in
            if case .text(let text) = content {
                return text
            }
            return nil
        }.joined(separator: "\n")

        return textContent
    }
}

// MARK: - Value Conversion Helper

extension Value {
    /// Helper to convert Any to MCP.Value
    init(from any: Any) throws {
        // Simple conversion for basic types.
        // Complex types might need JSON serialization/deserialization.
        if let string = any as? String {
            self = .string(string)
        } else if let int = any as? Int {
            self = .int(int)
        } else if let double = any as? Double {
            self = .double(double)
        } else if let bool = any as? Bool {
            self = .bool(bool)
        } else if let dict = any as? [String: Any] {
            var object: [String: Value] = [:]
            for (k, v) in dict {
                object[k] = try Value(from: v)
            }
            self = .object(object)
        } else if let array = any as? [Any] {
            let values = try array.map { try Value(from: $0) }
            self = .array(values)
        } else {
            // Fallback for unknown types -> try stringifying
            self = .string("\(any)")
        }
    }
}
