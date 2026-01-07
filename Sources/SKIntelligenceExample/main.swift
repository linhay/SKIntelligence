import Foundation
import SKIClients
import SKIntelligence

@main
struct SKIntelligenceExample {
    static func main() async {
        let env = ProcessInfo.processInfo.environment

        guard let token = env["OPENAI_API_KEY"], !token.isEmpty else {
            print("Missing OPENAI_API_KEY. Example will exit without calling a model.")
            print("Run like: OPENAI_API_KEY=... swift run SKIntelligenceExample")
            return
        }

        let model = env["OPENAI_MODEL"] ?? "gpt-4"

        let client = OpenAIClient()
            .token(token)
            .model(model)

        if let baseURL = env["OPENAI_BASE_URL"], !baseURL.isEmpty {
            do {
                _ = try client.url(baseURL)
            } catch {
                print("Invalid OPENAI_BASE_URL: \(baseURL). Error: \(error)")
                return
            }
        }

        let session = SKILanguageModelSession(client: client)

        do {
            let text = try await session.respond(to: "用一句话介绍 SKIntelligence")
            print("\n--- Non-streaming ---\n\(text)\n")

            print("--- Streaming ---")
            let stream = try await session.streamResponse(to: "用 3 个要点总结 SKIntelligence 的能力")
            for try await chunk in stream {
                if let t = chunk.text {
                    print(t, terminator: "")
                    fflush(stdout)
                }
                if let reason = chunk.reasoning, !reason.isEmpty {
                    // Optional: show reasoning in logs if your provider returns it.
                    // print("\n[reasoning]\n\(reason)\n")
                }
            }
            print("\n")
        } catch {
            print("Request failed: \(error)")
        }
    }
}
