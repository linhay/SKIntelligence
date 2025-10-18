import Accelerate
import Foundation

/// 针对大批量 Float 向量优化的余弦相似度索引。
public class SKISimilarityIndex<ID: Hashable> {
    
    public private(set) var dimension: Int?
    public private(set) var ids: [ID] = []
    private var normalizedMatrix: [Float] = []
    private var indexMap: [ID: Int] = [:]
    
    public var count: Int { ids.count }
    
    /// 创建固定维度的空索引。
    public init() {}
    
}

public extension SKISimilarityIndex {
    
    /// 计算查询向量与索引中所有向量的余弦相似度。
     func query(_ vector: [Float]) -> [Float] {
        guard !ids.isEmpty, let dimension else { return [] }
        precondition(vector.count == dimension, "Query vector must match index dimension")
        let normalizedQuery = normalize(vector)
        guard !normalizedQuery.isEmpty else { return [] }
        
        var scores = [Float](repeating: 0, count: count)
        normalizedQuery.withUnsafeBufferPointer { queryPtr in
            normalizedMatrix.withUnsafeBufferPointer { matrixPtr in
                // 使用新的 BLAS 接口进行高性能矩阵-向量乘法
                // C = alpha * A * B + beta * C
                // 其中 A 是 m x n 矩阵，B 是 n 维向量，C 是 m 维结果向量
                cblas_sgemv(
                    CblasRowMajor,           // 行主序存储
                    CblasNoTrans,            // 不转置矩阵
                    __LAPACK_int(count),     // 矩阵的行数 (m)
                    __LAPACK_int(dimension), // 矩阵的列数 (n)
                    1.0,                     // alpha = 1.0
                    matrixPtr.baseAddress!,  // 矩阵 A
                    __LAPACK_int(dimension), // 矩阵 A 的 leading dimension
                    queryPtr.baseAddress!,   // 向量 B
                    1,                       // 向量 B 的增量
                    0.0,                     // beta = 0.0
                    &scores,                 // 结果向量 C
                    1                        // 向量 C 的增量
                )
            }
        }
        
        return scores
    }
    
    /// 返回得分最高的前 k 个匹配结果及其标识符。
     func topK(_ vector: [Float], k: Int) -> [(id: ID, score: Float)] {
        let scores = query(vector)
        guard k > 0 else { return [] }
        let limit = min(k, scores.count)
        return scores.enumerated()
            .sorted(by: { $0.element > $1.element })
            .prefix(limit)
            .map { (ids[$0.offset], $0.element) }
    }
    
    /// 计算并返回所有向量的得分及其标识符，便于后续结合元数据筛选。
     func queryWithIDs(_ vector: [Float]) -> [(id: ID, score: Float)] {
        let scores = query(vector)
        return zip(ids, scores).map { ($0, $1) }
    }
    
}

public extension SKISimilarityIndex {
    
    func contains(id: ID) -> Bool {
        return indexMap[id] != nil
    }
    
    func vector(for id: ID) -> [Float]? {
        guard let dimension, let index = indexMap[id] else { return nil }
        let base = index * dimension
        let row = Array(normalizedMatrix[base..<(base + dimension)])
        return row
    }
    
    func allIDs() -> [ID] {
        return ids
    }
    
}

public extension SKISimilarityIndex {
    
    func append(vector: [[Float]], id: [ID]) {
        precondition(vector.count == id.count, "Vectors and IDs must have the same count")
        for (vec, idx) in zip(vector, id) {
            self.append(vector: vec, id: idx)
        }
    }

    func upsert(vector: [[Float]], id: [ID]) {
        precondition(vector.count == id.count, "Vectors and IDs must have the same count")
        for (vec, idx) in zip(vector, id) {
            self.upsert(vector: vec, id: idx)
        }
    }

    func update(vector: [[Float]], id: [ID]) {
        precondition(vector.count == id.count, "Vectors and IDs must have the same count")
        for (vec, idx) in zip(vector, id) {
            self.update(vector: vec, id: idx)
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

public extension SKISimilarityIndex {
    
    /// 添加新的向量与对应的标识符。
    func append(vector: [Float], id: ID) {
        precondition(indexMap[id] == nil, "Identifier already exists")
        if dimension == nil {
            self.dimension = vector.count
        }
        precondition(vector.count == dimension, "Vector dimension must match index dimension")
        let normalized = normalize(vector)
        ids.append(id)
        normalizedMatrix.append(contentsOf: normalized)
        indexMap[id] = ids.count - 1
    }
    
    /// 插入或更新指定标识符对应的向量。
    func upsert(vector: [Float], id: ID) {
        if let index = indexMap[id] {
            updateRow(at: index, with: vector)
        } else {
            append(vector: vector, id: id)
        }
    }
    
    /// 更新已存在的向量，若标识符不存在返回 false。
    @discardableResult
    func update(vector: [Float], id: ID) -> Bool {
        if dimension == nil {
            self.dimension = vector.count
        }
        guard let index = indexMap[id] else { return false }
        updateRow(at: index, with: vector)
        return true
    }
    
    /// 删除指定标识符对应的向量，若标识符不存在返回 false。
    @discardableResult
    func remove(_ id: ID) -> Bool {
        guard let dimension, let index = indexMap[id] else { return false }
        let lastIndex = ids.count - 1
        if index != lastIndex {
            swapRow(at: index, with: lastIndex)
        }
        let removedID = ids.removeLast()
        normalizedMatrix.removeLast(dimension)
        indexMap.removeValue(forKey: removedID)
        return true
    }
    
    func removeAll() {
        ids.removeAll()
        normalizedMatrix.removeAll()
        indexMap.removeAll()
        dimension = nil
    }
    
}

private extension SKISimilarityIndex {
    
     func updateRow(at index: Int, with vector: [Float]) {
        guard let dimension else { return }
        precondition(vector.count == dimension, "Vector dimension must match index dimension")
        let normalized = normalize(vector)
        let base = index * dimension
        normalizedMatrix.replaceSubrange(base..<(base + dimension), with: normalized)
    }
    
     func swapRow(at lhs: Int, with rhs: Int) {
        guard let dimension else { return }
        let lhsBase = lhs * dimension
        let rhsBase = rhs * dimension
        for offset in 0..<dimension {
            normalizedMatrix.swapAt(lhsBase + offset, rhsBase + offset)
        }
        ids.swapAt(lhs, rhs)
        indexMap[ids[lhs]] = lhs
        indexMap[ids[rhs]] = rhs
    }
    
     func writeRow(_ row: [Float], at index: Int) {
        guard let dimension else { return }
        precondition(row.count == dimension, "Row dimension must match index dimension")
        let base = index * dimension
        normalizedMatrix.replaceSubrange(base..<(base + dimension), with: row)
    }
    
     func normalize(_ vector: [Float]) -> [Float] {
        var normalizer = L2Normalizer<Float>()
        let normalized = normalizer.normalized(vector)
        guard let norm = normalizer.sqrootSumSquared, norm > 0 else { return .init(repeating: 0, count: vector.count) }
        return normalized
    }
}
