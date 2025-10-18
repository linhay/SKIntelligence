//
//  CosineSimilarityMatrixTests.swift
//  SKIntelligence
//
//  Created by linhey on 10/17/25.
//

import Testing
import SKIClip

struct CosineSimilarityMatrixTests {

    @Test("Basic case - values between 0 and 1")
    func testCosineSimilarity_basicCase() {
        let result = SKISimilarity(type: .cosine).compute(with: [1, 2, 3], matrix: [
            [1, 0, 0],
            [0, 1, 0],
            [0, 0, 1]
        ])
        #expect(result.count == 3)
        #expect(result.allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    @Test("Identical vectors should yield 1.0 similarity")
    func testCosineSimilarity_identicalVectors() {
        let v: [Float] = [1, 2, 3]
        let result = SKISimilarity(type: .cosine).compute(with: v, matrix: [v])

        #expect(abs(result.first! - 1.0) < 1e-6)
    }

    @Test("Orthogonal vectors should yield 0 similarity")
    func testCosineSimilarity_orthogonalVectors() {
        let v1: [Float] = [1, 0]
        let v2: [Float] = [0, 1]
        let result = SKISimilarity(type: .cosine).compute(with: v1, matrix: [v2])

        #expect(abs(result.first! - 0.0) < 1e-6)
    }

    @Test("Parallel vectors should yield 1.0 similarity")
    func testCosineSimilarity_parallelVectors() {
        let v1: [Float] = [1, 2, 3]
        let v2: [Float] = [2, 4, 6]
        let result = SKISimilarity(type: .cosine).compute(with: v1, matrix: [v2])
        #expect(abs(result.first! - 1.0) < 1e-6)
    }
}
