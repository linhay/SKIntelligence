//
//  SKIMCPIntegrationTests.swift
//  SKIntelligenceTests
//
//  Created by linhey on 6/14/25.
//

import MCP
import SKIClients
import XCTest
 import STJSON
 import SKIACP

@testable import SKIntelligence

final class SKIMCPIntegrationTests: XCTestCase {

    func testMCPToolRegistration() {
        // Mock Session
        // We cannot easily mock MCP.Client without a real server or dependency injection.
        // But we can test SKILanguageModelSession's registration logic.

        // This test mainly verifies that the code compiles and runs without crashing during registration.
        // Since we don't have a live MCP server, we can't fully integration test the tool call.

        // Create a dummy client using Builder Pattern
        let client = OpenAIClient()
            .token("test")
            .model("gpt-4")
        let session = SKILanguageModelSession(client: client)

        // We can't init SKIMCPTool directly without a valid SKIMCPClient, which needs an endpoint.
        // And SKIMCPClient needs an endpoint.

        let endpoint = URL(string: "http://localhost:8000/sse")!
        let mcpClient = SKIMCPClient(endpoint: endpoint)

        // We can't create MCP.Tool easily as it is from the SDK.
        // Assuming we can init MCP.Tool manually.
        let toolSchema = MCP.Value.object([
            "type": .string("object"),
            "properties": .object([
                "location": .object([
                    "type": .string("string")
                ])
            ]),
        ])

        let mcpTool = MCP.Tool(
            name: "mcp_weather", description: "Get weather", inputSchema: toolSchema)
        let skiMCPTool = SKIMCPTool(mcpTool: mcpTool, client: mcpClient)

        // Register
        Task {
            await session.register(mcpTool: skiMCPTool)

            // Verify enabled tools
            if let tools = await session.enabledTools() {
                XCTAssertTrue(
                    tools.contains(where: {
                        if case .function(let name, _, _, _) = $0 {
                            return name == "mcp_weather"
                        }
                        return false
                    }))
            } else {
                XCTFail("No tools enabled")
            }
        }
    }
}
