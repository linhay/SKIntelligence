import Foundation

public struct SKITokenUsageSnapshot: Sendable, Equatable, Codable {
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int
    public let reasoningTokens: Int
    public let requestsCount: Int
    public let updatedAt: Date?

    public init(
        promptTokens: Int = 0,
        completionTokens: Int = 0,
        totalTokens: Int = 0,
        reasoningTokens: Int = 0,
        requestsCount: Int = 0,
        updatedAt: Date? = nil
    ) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.reasoningTokens = reasoningTokens
        self.requestsCount = requestsCount
        self.updatedAt = updatedAt
    }
}
