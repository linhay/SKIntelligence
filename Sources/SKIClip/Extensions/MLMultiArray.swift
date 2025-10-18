//
// For licensing see accompanying LICENSE file.
// Copyright (C) 2024 Apple Inc. All Rights Reserved.
//

import CoreML
import CoreImage
import QuartzCore

public extension String {
    
    /// 计算两个字符串的 Levenshtein 距离
    func levenshteinDistance(to other: String) -> Int {
        let a = Array(self)
        let b = Array(other)
        var dp = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        
        for i in 0...a.count { dp[i][0] = i }
        for j in 0...b.count { dp[0][j] = j }
        
        for i in 1...a.count {
            for j in 1...b.count {
                if a[i-1] == b[j-1] {
                    dp[i][j] = dp[i-1][j-1]
                } else {
                    dp[i][j] = min(dp[i-1][j-1], min(dp[i-1][j], dp[i][j-1])) + 1
                }
            }
        }
        return dp[a.count][b.count]
    }
    
}

public extension Data {
    
    /// 从 Data 转换成 [Element]
    func bindMemory<V>(to element: V.Type) -> [V] {
        let count = self.count / MemoryLayout<V>.size
        return self.withUnsafeBytes { rawBuffer in
            let buffer = rawBuffer.bindMemory(to: V.self)
            return Array(buffer.prefix(count))
        }
    }
    
    /// 从 Data 转换成 [Element]
    func bindMemoryToFloat() -> [Float] {
        bindMemory(to: Float.self)
    }
    
    
}

public extension Array {
    
    /// 把 [Element] 转换成 Data
    func toData() -> Data {
        return withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
    }
    
}

public extension Array where Element == Float {
    func cosineSimilarity(_ e2: [Float]) -> Float {
        // read the values out of the MLMultiArray in bulk
        let e1 = self
        // Get the dot product of the two embeddings
        let dotProduct: Float = zip(e1, e2).reduce(0.0) { $0 + $1.0 * $1.1 }

        // Get the magnitudes of the two embeddings
        let magnitude1: Float = sqrt(e1.reduce(0) { $0 + pow($1, 2) })
        let magnitude2: Float = sqrt(e2.reduce(0) { $0 + pow($1, 2) })

        // Get the cosine similarity
        let similarity = dotProduct / (magnitude1 * magnitude2)
        return similarity
    }
}

public extension MLMultiArray {
    
    var floats: [Float] {
        self.withUnsafeBufferPointer(ofType: Float.self) { ptr in
            Array(ptr)
        }
    }
    
}
