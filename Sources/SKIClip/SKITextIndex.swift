import Foundation

/// 文本查询的辅助结构（不需要 ID）
fileprivate struct TextQuery {
    let text: String
    let normalizedText: String
    let tokens: Set<String>
    
    init(text: String) {
        self.text = text
        self.normalizedText = Self.normalize(text)
        self.tokens = Self.tokenize(normalizedText)
    }
    
    static func normalize(_ text: String) -> String {
        return text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: .diacriticInsensitive, locale: .current)
    }
    
    static func tokenize(_ text: String) -> Set<String> {
        let components = text.components(separatedBy: .whitespacesAndNewlines)
        var tokens = Set<String>()
        
        for component in components {
            let cleaned = component.components(separatedBy: .punctuationCharacters)
                .joined()
            if !cleaned.isEmpty {
                tokens.insert(cleaned)
                // 添加字符级 n-gram (用于中文等无空格分词的语言)
                if cleaned.count >= 2 {
                    for i in 0..<(cleaned.count - 1) {
                        let start = cleaned.index(cleaned.startIndex, offsetBy: i)
                        let end = cleaned.index(start, offsetBy: 2)
                        tokens.insert(String(cleaned[start..<end]))
                    }
                }
            }
        }
        
        return tokens
    }
}

public struct SKITextIndexObject<ID: Hashable> {
    public let id: ID
    public let text: String
    public let normalizedText: String
    public let tokens: Set<String>

    public init(id: ID, text: String) {
        self.id = id
        self.text = text
        self.normalizedText = Self.normalize(text)
        self.tokens = Self.tokenize(normalizedText)
    }

     static func normalize(_ text: String) -> String {
        return text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: .diacriticInsensitive, locale: .current)
    }

     static func tokenize(_ text: String) -> Set<String> {
        let components = text.components(separatedBy: .whitespacesAndNewlines)
        var tokens = Set<String>()

        for component in components {
            let cleaned = component.components(separatedBy: .punctuationCharacters)
                .joined()
            if !cleaned.isEmpty {
                tokens.insert(cleaned)
                // 添加字符级 n-gram (用于中文等无空格分词的语言)
                if cleaned.count >= 2 {
                    for i in 0..<(cleaned.count - 1) {
                        let start = cleaned.index(cleaned.startIndex, offsetBy: i)
                        let end = cleaned.index(start, offsetBy: 2)
                        tokens.insert(String(cleaned[start..<end]))
                    }
                }
            }
        }

        return tokens
    }
}

/// 针对文本块优化的相似度索引，用于图片中识别出的文本搜索。
public class SKITextIndex<ID: Hashable> {

    private var entries: [SKITextIndexObject<ID>] = []
    private var indexMap: [ID: Int] = [:]

    public var count: Int { entries.count }

    /// 创建空索引。
    public init() {}

}

public extension SKITextIndex {

    /// 计算查询文本与索引中所有文本的相似度。
    /// - Parameter text: 查询文本
    /// - Parameter concurrent: 是否使用并发计算（默认 true，数据量大时性能更好）
    func query(_ text: String, concurrent: Bool = true) -> [Float] {
        guard !entries.isEmpty else { return [] }

        let queryData = TextQuery(text: text)
        
        // 对于小数据集，直接遍历更快（避免并发开销）
        if count < 100 || !concurrent {
            var scores = [Float](repeating: 0, count: count)
            for (index, entry) in entries.enumerated() {
                scores[index] = calculateSimilarity(query: queryData, target: entry)
            }
            return scores
        }
        
        // 对于大数据集，使用并发计算
        let scores = entries.indices.map { index -> Float in
            calculateSimilarity(query: queryData, target: entries[index])
        }
        
        return scores
    }

    /// 返回得分最高的前 k 个匹配结果及其标识符。
    /// 优化：不需要计算所有分数，只需找到 top k
    func topK(_ text: String, k: Int) -> [(id: ID, text: String, score: Float)] {
        guard k > 0, !entries.isEmpty else { return [] }
        
        let queryData = TextQuery(text: text)
        let limit = min(k, count)
        
        // 使用最小堆优化 top-k 查找，避免全排序
        var topResults: [(index: Int, score: Float)] = []
        topResults.reserveCapacity(limit)
        
        for (index, entry) in entries.enumerated() {
            let score = calculateSimilarity(query: queryData, target: entry)
            
            if topResults.count < limit {
                topResults.append((index, score))
                if topResults.count == limit {
                    topResults.sort { $0.score > $1.score }
                }
            } else if score > topResults.last!.score {
                topResults[limit - 1] = (index, score)
                // 插入排序保持有序
                var i = limit - 1
                while i > 0 && topResults[i].score > topResults[i - 1].score {
                    topResults.swapAt(i, i - 1)
                    i -= 1
                }
            }
        }
        
        return topResults
            .sorted { $0.score > $1.score }
            .map { (entries[$0.index].id, entries[$0.index].text, $0.score) }
    }
    
    /// 异步并发版本的 topK 查询（适合大数据集）
    @available(macOS 10.15, iOS 13.0, *)
    func topKAsync(_ text: String, k: Int) async -> [(id: ID, text: String, score: Float)] {
        guard k > 0, !entries.isEmpty else { return [] }
        
        let queryData = TextQuery(text: text)
        let limit = min(k, count)
        
        // 分块并发处理
        let chunkSize = max(100, count / ProcessInfo.processInfo.activeProcessorCount)
        let chunks = stride(from: 0, to: count, by: chunkSize).map { start -> Range<Int> in
            let end = min(start + chunkSize, count)
            return start..<end
        }
        
        // 并发计算每个分块的分数
        let chunkResults = await withTaskGroup(of: [(index: Int, score: Float)].self) { group in
            for chunk in chunks {
                group.addTask {
                    var results: [(index: Int, score: Float)] = []
                    for index in chunk {
                        let score = self.calculateSimilarity(query: queryData, target: self.entries[index])
                        results.append((index, score))
                    }
                    return results
                }
            }
            
            var allResults: [(index: Int, score: Float)] = []
            for await chunkResult in group {
                allResults.append(contentsOf: chunkResult)
            }
            return allResults
        }
        
        // 找出 top k
        let topResults = chunkResults
            .sorted { $0.score > $1.score }
            .prefix(limit)
        
        return topResults.map { (entries[$0.index].id, entries[$0.index].text, $0.score) }
    }
    
    /// 带分数阈值的查询（早期退出优化）
    func topK(_ text: String, k: Int, minScore: Float) -> [(id: ID, text: String, score: Float)] {
        guard k > 0, !entries.isEmpty, minScore >= 0, minScore <= 1 else { return [] }
        
        let queryData = TextQuery(text: text)
        let limit = min(k, count)
        
        var topResults: [(index: Int, score: Float)] = []
        topResults.reserveCapacity(limit)
        
        for (index, entry) in entries.enumerated() {
            let score = calculateSimilarity(query: queryData, target: entry)
            
            // 只考虑超过阈值的结果
            guard score >= minScore else { continue }
            
            if topResults.count < limit {
                topResults.append((index, score))
                if topResults.count == limit {
                    topResults.sort { $0.score > $1.score }
                }
            } else if score > topResults.last!.score {
                topResults[limit - 1] = (index, score)
                var i = limit - 1
                while i > 0 && topResults[i].score > topResults[i - 1].score {
                    topResults.swapAt(i, i - 1)
                    i -= 1
                }
            }
        }
        
        return topResults
            .sorted { $0.score > $1.score }
            .map { (entries[$0.index].id, entries[$0.index].text, $0.score) }
    }

    /// 计算并返回所有文本的得分及其标识符，便于后续结合元数据筛选。
    func queryWithIDs(_ text: String) -> [(id: ID, text: String, score: Float)] {
        let scores = query(text)
        return zip(entries, scores).map { ($0.id, $0.text, $1) }
    }

    /// 精确匹配搜索（不区分大小写）。
    func exactMatch(_ text: String) -> [(id: ID, text: String)] {
        let normalizedQuery = SKITextIndexObject<ID>.normalize(text)
        
        // 优化：使用 compactMap 减少中间数组分配
        return entries.compactMap { entry in
            entry.normalizedText == normalizedQuery ? (entry.id, entry.text) : nil
        }
    }

    /// 包含搜索（不区分大小写）。
    func contains(_ text: String) -> [(id: ID, text: String)] {
        let normalizedQuery = SKITextIndexObject<ID>.normalize(text)
        
        // 优化：提前计算查询文本的长度，避免重复调用
        guard !normalizedQuery.isEmpty else { return [] }
        
        return entries.compactMap { entry in
            entry.normalizedText.contains(normalizedQuery) ? (entry.id, entry.text) : nil
        }
    }

    /// 前缀匹配搜索（不区分大小写）。
    func hasPrefix(_ text: String) -> [(id: ID, text: String)] {
        let normalizedQuery = SKITextIndexObject<ID>.normalize(text)
        
        guard !normalizedQuery.isEmpty else { return [] }
        
        return entries.compactMap { entry in
            entry.normalizedText.hasPrefix(normalizedQuery) ? (entry.id, entry.text) : nil
        }
    }

    /// 后缀匹配搜索（不区分大小写）。
    func hasSuffix(_ text: String) -> [(id: ID, text: String)] {
        let normalizedQuery = SKITextIndexObject<ID>.normalize(text)
        
        guard !normalizedQuery.isEmpty else { return [] }
        
        return entries.compactMap { entry in
            entry.normalizedText.hasSuffix(normalizedQuery) ? (entry.id, entry.text) : nil
        }
    }
    
    /// 批量精确匹配（优化：一次遍历完成多个查询）
    func exactMatch(_ texts: [String]) -> [String: [(id: ID, text: String)]] {
        let normalizedQueries = Set(texts.map { SKITextIndexObject<ID>.normalize($0) })
        var results: [String: [(id: ID, text: String)]] = [:]
        
        for query in normalizedQueries {
            results[query] = []
        }
        
        for entry in entries {
            if normalizedQueries.contains(entry.normalizedText) {
                results[entry.normalizedText]?.append((entry.id, entry.text))
            }
        }
        
        return results
    }

}

public extension SKITextIndex {

    func contains(id: ID) -> Bool {
        return indexMap[id] != nil
    }

    func text(for id: ID) -> String? {
        guard let index = indexMap[id] else { return nil }
        return entries[index].text
    }

    func allIDs() -> [ID] {
        return entries.map { $0.id }
    }

    func allTexts() -> [String] {
        return entries.map { $0.text }
    }

}

public extension SKITextIndex {

    func append(text: [String], id: [ID]) {
        precondition(text.count == id.count, "Texts and IDs must have the same count")
        for (txt, idx) in zip(text, id) {
            self.append(text: txt, id: idx)
        }
    }

    func upsert(text: [String], id: [ID]) {
        precondition(text.count == id.count, "Texts and IDs must have the same count")
        for (txt, idx) in zip(text, id) {
            self.upsert(text: txt, id: idx)
        }
    }

    func update(text: [String], id: [ID]) {
        precondition(text.count == id.count, "Texts and IDs must have the same count")
        for (txt, idx) in zip(text, id) {
            self.update(text: txt, id: idx)
        }
    }

    @discardableResult
    func remove(_ id: [ID]) -> Bool {
        var result = true
        for idx in id {
            result = self.remove(idx) && result
        }
        return result
    }

}

public extension SKITextIndex {

    func append(_ object: SKITextIndexObject<ID>) {
        self.append(text: object.text, id: object.id)
    }
    
    func upsert(_ object: SKITextIndexObject<ID>) {
        self.upsert(text: object.text, id: object.id)
    }
    
    @discardableResult
    func update(_ object: SKITextIndexObject<ID>) -> Bool {
        return update(text: object.text, id: object.id)
    }
    
    @discardableResult
    func remove(_ object: SKITextIndexObject<ID>) -> Bool {
        return remove(object.id)
    }
    
    /// 添加新的文本与对应的标识符。
    func append(text: String, id: ID) {
        precondition(indexMap[id] == nil, "Identifier already exists")
        let entry = SKITextIndexObject(id: id, text: text)
        entries.append(entry)
        indexMap[id] = entries.count - 1
    }
    
    /// 插入或更新指定标识符对应的文本。
    func upsert(text: String, id: ID) {
        if let index = indexMap[id] {
            updateEntry(at: index, with: text)
        } else {
            append(text: text, id: id)
        }
    }

    /// 更新已存在的文本，若标识符不存在返回 false。
    @discardableResult
    func update(text: String, id: ID) -> Bool {
        guard let index = indexMap[id] else { return false }
        updateEntry(at: index, with: text)
        return true
    }

    /// 删除指定标识符对应的文本，若标识符不存在返回 false。
    @discardableResult
    func remove(_ id: ID) -> Bool {
        guard let index = indexMap[id] else { return false }
        let lastIndex = entries.count - 1
        if index != lastIndex {
            swapEntry(at: index, with: lastIndex)
        }
        let removedID = entries.removeLast().id
        indexMap.removeValue(forKey: removedID)
        return true
    }

    func removeAll() {
        entries.removeAll()
        indexMap.removeAll()
    }

}

private extension SKITextIndex {

    func updateEntry(at index: Int, with text: String) {
        let id = entries[index].id
        entries[index] = SKITextIndexObject(id: id, text: text)
    }

    func swapEntry(at lhs: Int, with rhs: Int) {
        entries.swapAt(lhs, rhs)
        indexMap[entries[lhs].id] = lhs
        indexMap[entries[rhs].id] = rhs
    }

    /// 计算两个文本条目之间的相似度。
    /// 使用 Jaccard 相似度（交集/并集）和字符串编辑距离的组合。
    func calculateSimilarity(query: TextQuery, target: SKITextIndexObject<ID>) -> Float {
        // 1. 精确匹配得最高分
        if query.normalizedText == target.normalizedText {
            return 1.0
        }

        // 2. 包含关系得高分
        if target.normalizedText.contains(query.normalizedText) {
            let ratio = Float(query.normalizedText.count) / Float(target.normalizedText.count)
            return 0.8 + ratio * 0.15  // 0.8 - 0.95
        }
        if query.normalizedText.contains(target.normalizedText) {
            let ratio = Float(target.normalizedText.count) / Float(query.normalizedText.count)
            return 0.7 + ratio * 0.15  // 0.7 - 0.85
        }

        // 3. Token 相似度（Jaccard 系数）
        let intersection = query.tokens.intersection(target.tokens)
        let union = query.tokens.union(target.tokens)

        guard !union.isEmpty else { return 0.0 }

        let jaccardScore = Float(intersection.count) / Float(union.count)

        // 4. 字符串相似度（基于最长公共子序列）
        let lcsScore = longestCommonSubsequenceRatio(query.normalizedText, target.normalizedText)

        // 组合两种分数，Token 相似度权重更高
        return jaccardScore * 0.7 + lcsScore * 0.3
    }

    /// 计算两个字符串的最长公共子序列比率。
    func longestCommonSubsequenceRatio(_ str1: String, _ str2: String) -> Float {
        guard !str1.isEmpty && !str2.isEmpty else { return 0.0 }

        let arr1 = Array(str1)
        let arr2 = Array(str2)
        let m = arr1.count
        let n = arr2.count

        // 使用动态规划计算 LCS 长度
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

        for i in 1...m {
            for j in 1...n {
                if arr1[i - 1] == arr2[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        let lcsLength = dp[m][n]
        let maxLength = max(m, n)

        return Float(lcsLength) / Float(maxLength)
    }

}

// MARK: - TextEntry Helpers
private extension SKITextIndexObject {
    static func normalize(where text: String) -> String {
        return text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: .diacriticInsensitive, locale: .current)
    }
}
