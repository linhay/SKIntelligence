//
// For licensing see accompanying LICENSE file.
// Copyright (C) 2024 Apple Inc. All Rights Reserved.
//

import CoreML
import CoreImage
import QuartzCore

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
    
    func cosineSimilarity(_ other: MLMultiArray) -> Float {
        return floats.cosineSimilarity(other.floats)
    }
    
}
