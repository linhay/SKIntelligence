//
//  VectorNormalizationTests.swift
//  SKIntelligence
//
//  Created by linhey on 8/28/25.
//

import XCTest
import SKIClip

#if canImport(CoreML) 

// MARK: - L2Normalizer 单元测试
final class L2NormalizerTests: XCTestCase {

    func testNormalizedVector() {
        var normalizer = L2Normalizer<Double>()
        let vector: [Double] = [3, 4]

        let normalizedVector = normalizer.normalized(vector)

        // 检查归一化向量
        XCTAssertEqual(normalizedVector.count, vector.count)
        
        // 检查 L2 范数是否接近 1
        let l2Norm = sqrt(normalizedVector.reduce(0) { $0 + $1 * $1 })
        XCTAssertEqual(l2Norm, 1.0, accuracy: 1e-10)
        
        // 检查单值归一化
        let normalizedValue = normalizer.normalize(3)
        XCTAssertEqual(normalizedValue, 3 / 5.0, accuracy: 1e-10)
        
        // 检查单值反归一化
        let denormalizedValue = normalizer.denormalize(normalizedValue)
        XCTAssertEqual(denormalizedValue, 3.0, accuracy: 1e-10)
    }

    func testZeroVector() {
        var normalizer = L2Normalizer<Double>()
        let vector: [Double] = [0, 0, 0]

        let normalizedVector = normalizer.normalized(vector)

        // 全零向量归一化应该返回原向量
        XCTAssertEqual(normalizedVector, vector)
        
        // 单值归一化 / 反归一化也返回原值
        XCTAssertEqual(normalizer.normalize(0), 0)
        XCTAssertEqual(normalizer.denormalize(0), 0)
    }

    func testNegativeValues() {
        var normalizer = L2Normalizer<Double>()
        let vector: [Double] = [-3, 4]

        let normalizedVector = normalizer.normalized(vector)

        // L2 范数仍然为 1
        let l2Norm = sqrt(normalizedVector.reduce(0) { $0 + $1 * $1 })
        XCTAssertEqual(l2Norm, 1.0, accuracy: 1e-10)

        // 检查负数是否正确归一化
        XCTAssertEqual(normalizedVector[0], -3 / 5.0, accuracy: 1e-10)
        XCTAssertEqual(normalizedVector[1], 4 / 5.0, accuracy: 1e-10)
    }
}

#endif
