import Testing
import Foundation
import JSONSchemaBuilder
import SKIntelligence
import SKITools
import SKIClients

#if canImport(CoreLocation)

@Test func test_tavily_search_tool() async throws {
    guard ProcessInfo.processInfo.environment["RUN_LIVE_PROVIDER_TESTS"] == "1" else {
        return
    }
    let client = OpenAIClient()
        .model(.deepseek_chat)
        .token(Keys.deepseek)
        .url(.deepseek)
    let session = SKILanguageModelSession(client: client,
                                          tools: [
                                            SKIToolLocalDate(),
                                            SKIToolLocalLocation(),
                                            SKIToolReverseGeocode(),
                                            SKIToolTavilySearch(apiKey: Keys.tavilys.randomElement()!)
                                          ])
    let prompt: SKIPrompt = """
        我想知道今天 swift 语言有什么新的动态？请帮我搜索一下。
        """
    let response = try await session.respond(to: prompt)
    print(response)
    
}

#endif
