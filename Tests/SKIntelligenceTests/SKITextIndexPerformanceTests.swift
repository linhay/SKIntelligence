import XCTest
 import STJSON
 import SKIACP
@testable import SKIClip

#if canImport(CoreML)

final class SKITextIndexPerformanceTests: XCTestCase {
    
    var textIndex: SKITextIndex<String>!
    
    override func setUp() {
        super.setUp()
        textIndex = SKITextIndex<String>()
        
        // 添加大量测试数据
        let sampleTexts = [
            "Apple iPhone 15 Pro Max",
            "Samsung Galaxy S24 Ultra",
            "Google Pixel 8 Pro",
            "OnePlus 12 Pro",
            "Xiaomi 14 Ultra",
            "Huawei Mate 60 Pro",
            "OPPO Find X7 Ultra",
            "vivo X100 Pro",
            "Realme GT5 Pro",
            "Nothing Phone 2",
            "MacBook Pro 16-inch M3",
            "MacBook Air 15-inch",
            "iPad Pro 12.9-inch",
            "iPad Air 11-inch",
            "Apple Watch Series 9",
            "AirPods Pro 2nd Gen",
            "HomePod mini",
            "Apple TV 4K",
            "Magic Keyboard",
            "Magic Mouse"
        ]
        
        // 生成 1000 条数据
        for i in 0..<1000 {
            let text = sampleTexts[i % sampleTexts.count] + " \(i)"
            textIndex.append(text: text, id: "id_\(i)")
        }
    }
    
    override func tearDown() {
        textIndex = nil
        super.tearDown()
    }
    
    // MARK: - Performance Tests
    
    func testQueryPerformance() {
        measure {
            let scores = textIndex.query("iPhone 15", concurrent: false)
            XCTAssertEqual(scores.count, 1000)
        }
    }
    
    func testQueryConcurrentPerformance() {
        measure {
            let scores = textIndex.query("iPhone 15", concurrent: true)
            XCTAssertEqual(scores.count, 1000)
        }
    }
    
    func testTopKPerformance() {
        measure {
            let results = textIndex.topK("iPhone 15", k: 10)
            XCTAssertGreaterThan(results.count, 0)
        }
    }
    
    func testTopKWithMinScorePerformance() {
        measure {
            let results = textIndex.topK("iPhone 15", k: 10, minScore: 0.5)
            XCTAssertGreaterThan(results.count, 0)
        }
    }
    
    func testExactMatchPerformance() {
        measure {
            let results = textIndex.exactMatch("Apple iPhone 15 Pro Max 500")
            XCTAssertGreaterThan(results.count, 0)
        }
    }
    
    func testContainsPerformance() {
        measure {
            let results = textIndex.contains("Pro")
            XCTAssertGreaterThan(results.count, 0)
        }
    }
    
    func testBatchExactMatchPerformance() {
        let queries = ["iPhone", "Samsung", "Google", "MacBook", "iPad"]
        
        measure {
            let results = textIndex.exactMatch(queries)
            XCTAssertEqual(results.keys.count, queries.count)
        }
    }
    
    // MARK: - Comparison Tests
    
    func testCompareTopKMethods() {
        print("\n=== Performance Comparison: Top-K Methods ===")
        
        // 方法 1: 使用优化的 topK
        let time1 = measureTime {
            _ = textIndex.topK("iPhone", k: 10)
        }
        print("Optimized topK: \(String(format: "%.4f", time1))s")
        
        // 方法 2: 使用传统的全排序方法（模拟）
        let time2 = measureTime {
            let scores = textIndex.query("iPhone", concurrent: false)
            _ = scores.enumerated()
                .sorted(by: { $0.element > $1.element })
                .prefix(10)
        }
        print("Full sort method: \(String(format: "%.4f", time2))s")
        
        print("Speed improvement: \(String(format: "%.2f", time2 / time1))x faster")
    }
    
    func testCompareConcurrentVsSequential() {
        print("\n=== Performance Comparison: Concurrent vs Sequential ===")
        
        let time1 = measureTime {
            _ = textIndex.query("iPhone", concurrent: false)
        }
        print("Sequential query: \(String(format: "%.4f", time1))s")
        
        let time2 = measureTime {
            _ = textIndex.query("iPhone", concurrent: true)
        }
        print("Concurrent query: \(String(format: "%.4f", time2))s")
        
        if time1 > time2 {
            print("Speed improvement: \(String(format: "%.2f", time1 / time2))x faster with concurrency")
        } else {
            print("Sequential is faster for this data size (concurrency overhead)")
        }
    }
    
    // MARK: - Scale Tests
    
    func testLargeDataset() {
        // 测试更大的数据集
        let largeIndex = SKITextIndex<Int>()
        
        print("\n=== Large Dataset Test ===")
        print("Adding 10,000 entries...")
        
        let addTime = measureTime {
            for i in 0..<10000 {
                largeIndex.append(text: "Sample text entry number \(i)", id: i)
            }
        }
        print("Time to add 10,000 entries: \(String(format: "%.4f", addTime))s")
        
        print("\nQuerying top 10 from 10,000 entries...")
        let queryTime = measureTime {
            _ = largeIndex.topK("Sample text", k: 10)
        }
        print("Query time: \(String(format: "%.4f", queryTime))s")
        
        XCTAssertEqual(largeIndex.count, 10000)
    }
    
    func testMemoryEfficiency() {
        print("\n=== Memory Efficiency Test ===")
        
        let initialMemory = reportMemoryUsage()
        print("Initial memory: \(initialMemory) MB")
        
        // 添加大量数据
        for i in 0..<5000 {
            textIndex.append(text: "Additional entry \(i) with some text content", id: "additional_\(i)")
        }
        
        let finalMemory = reportMemoryUsage()
        print("Final memory: \(finalMemory) MB")
        print("Memory increase: \(String(format: "%.2f", finalMemory - initialMemory)) MB")
        print("Average per entry: \(String(format: "%.4f", (finalMemory - initialMemory) / 5.0)) KB")
    }
    
    // MARK: - Helper Methods
    
    private func measureTime(_ block: () -> Void) -> TimeInterval {
        let start = Date()
        block()
        return Date().timeIntervalSince(start)
    }
    
    private func reportMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return Double(info.resident_size) / 1024.0 / 1024.0
        } else {
            return 0
        }
    }
    
    // MARK: - Async Performance Tests
    
    @available(macOS 10.15, iOS 13.0, *)
    func testTopKAsyncPerformance() async {
        print("\n=== Async Performance Test ===")
        
        let asyncTime = await measureTimeAsync { [self] in
            _ = await self.textIndex.topKAsync("iPhone", k: 10)
        }
        print("Async topK time: \(String(format: "%.4f", asyncTime))s")
        
        let syncTime = measureTime {
            _ = self.textIndex.topK("iPhone", k: 10)
        }
        print("Sync topK time: \(String(format: "%.4f", syncTime))s")
    }
    
    @available(macOS 10.15, iOS 13.0, *)
    private func measureTimeAsync(_ block: @escaping () async -> Void) async -> TimeInterval {
        let start = Date()
        await block()
        return Date().timeIntervalSince(start)
    }
}

#endif
