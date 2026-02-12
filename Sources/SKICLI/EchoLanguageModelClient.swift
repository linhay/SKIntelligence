import Foundation
import HTTPTypes
import SKIntelligence

struct EchoLanguageModelClient: SKILanguageModelClient {
    func respond(_ body: ChatRequestBody) async throws -> sending SKIResponse<ChatResponseBody> {
        let input = body.messages.compactMap { message -> String? in
            switch message {
            case .user(let content, _):
                if case .text(let text) = content {
                    return text
                }
                return nil
            default:
                return nil
            }
        }.joined(separator: "\n")

        let escaped = input
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")

        let payload = """
        {
          "choices": [
            {
              "finish_reason": "stop",
              "message": {
                "content": "[echo] \(escaped)",
                "role": "assistant"
              }
            }
          ],
          "created": 0,
          "model": "echo-model"
        }
        """

        return try SKIResponse<ChatResponseBody>(
            httpResponse: HTTPResponse(status: .ok),
            data: Data(payload.utf8)
        )
    }
}
