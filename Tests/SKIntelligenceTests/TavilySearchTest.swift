import Testing
import Foundation
import JSONSchemaBuilder
import SKIntelligence
import SKITools

@Test func test_tavily_search_tool() async throws {
    let client = try OpenAIClient(url: "https://api.deepseek.com/v1/chat/completions",
                                  token: Keys.deepseek)
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
