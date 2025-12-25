#if canImport(CoreML)
//
//  CosineSimilarityMatrix.swift
//  SKIntelligence
//
//  Created by linhey on 10/17/25.
//

import Accelerate
import Foundation

/// High-performance cosine similarity utilities for Float and Double.
///
/// This file exposes two concrete types:
/// - `CosineSimilarityMatrixFloat` for `Float` data
/// - `CosineSimilarityMatrixDouble` for `Double` data
///
/// The prior generic design `CosineSimilarityMatrix<Element: BinaryFloatingPoint> where Element == Float || Element == Double`
/// is not valid in Swift 6 mode. Providing two concrete types keeps the API simple and avoids problematic
/// generic `where` constraints while still using vDSP for performance.

public struct SKISimilarity<Element: BinaryFloatingPoint> {
    
    public enum SimilarityType {
        case cosine
    }
    
    public let type: SimilarityType
    
    public init(type: SimilarityType) {
        self.type = type
    }
    
    public func compute(
        with vector: [Element],
        matrix: [[Element]]
    ) -> [Element] where Element == Float {
        switch type {
        case .cosine:
            return CosineSimilarityMatrixFloat().compute(with: vector, matrix: matrix)
        }
    }
    
}


struct CosineSimilarityMatrixFloat {
    
    /// 计算向量与矩阵中每个向量（行或列）的余弦相似度
    public func compute(with vector: [Float], matrix: [[Float]]) -> [Float] {
        if matrix.isEmpty { return [] }
        
        let vectors: [[Float]] = matrix
        precondition(vectors.first?.count == vector.count, "维度不匹配")
        
        var results = [Float](repeating: 0, count: vectors.count)
        
        let vNorm = max(norm(vector), Float.leastNonzeroMagnitude)
        
        DispatchQueue.concurrentPerform(iterations: vectors.count) { i in
            let col = vectors[i]
            let dot = dotProduct(vector, col)
            let cNorm = max(norm(col), Float.leastNonzeroMagnitude)
            results[i] = dot / (vNorm * cNorm)
        }
        
        return results
    }
    
    // MARK: - Private helpers
    
    private func norm(_ v: [Float]) -> Float {
        var result: Float = 0
        vDSP_svesq(v, 1, &result, vDSP_Length(v.count))
        return sqrtf(result)
    }
    
    private func dotProduct(_ a: [Float], _ b: [Float]) -> Float {
        var result: Float = 0
        vDSP_dotpr(a, 1, b, 1, &result, vDSP_Length(a.count))
        return result
    }
    
}
#endif
