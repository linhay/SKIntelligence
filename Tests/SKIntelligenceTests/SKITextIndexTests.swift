import XCTest
@testable import SKIClip

final class SKITextIndexTests: XCTestCase {
    
    var textIndex: SKITextIndex<String>!
    
    override func setUp() {
        super.setUp()
        textIndex = SKITextIndex<String>()
    }
    
    override func tearDown() {
        textIndex = nil
        super.tearDown()
    }
    
    // MARK: - Basic Operations Tests
    
    func testAppendAndQuery() {
        // 添加一些文本块（模拟从图片中识别的文本）
        textIndex.append(text: "Apple iPhone 15 Pro", id: "text1")
        textIndex.append(text: "Samsung Galaxy S24", id: "text2")
        textIndex.append(text: "iPhone 14 Plus", id: "text3")
        textIndex.append(text: "MacBook Pro 16-inch", id: "text4")
        
        XCTAssertEqual(textIndex.count, 4)
        XCTAssertTrue(textIndex.contains(id: "text1"))
        XCTAssertEqual(textIndex.text(for: "text1"), "Apple iPhone 15 Pro")
    }
    
    func testTopKQuery() {
        // 添加测试数据
        textIndex.append(text: "iPhone 15 Pro Max", id: "text1")
        textIndex.append(text: "iPhone 15 Pro", id: "text2")
        textIndex.append(text: "iPhone 14", id: "text3")
        textIndex.append(text: "Samsung Galaxy", id: "text4")
        textIndex.append(text: "MacBook Pro", id: "text5")
        
        // 查询 "iPhone 15"
        let results = textIndex.topK("iPhone 15", k: 3)
        
        XCTAssertEqual(results.count, 3)
        // 前两个结果应该包含 "iPhone 15"
        XCTAssertTrue(results[0].text.contains("iPhone 15"))
        XCTAssertTrue(results[1].text.contains("iPhone 15"))
        print("Top 3 results for 'iPhone 15':")
        for (index, result) in results.enumerated() {
            print("\(index + 1). \(result.text) - Score: \(result.score)")
        }
    }
    
    func testExactMatch() {
        textIndex.append(text: "Hello World", id: "text1")
        textIndex.append(text: "hello world", id: "text2")
        textIndex.append(text: "Hello Swift", id: "text3")
        
        let results = textIndex.exactMatch("hello world")
        
        XCTAssertEqual(results.count, 2) // 不区分大小写
        XCTAssertTrue(results.contains(where: { $0.id == "text1" }))
        XCTAssertTrue(results.contains(where: { $0.id == "text2" }))
    }
    
    func testContainsSearch() {
        textIndex.append(text: "Total Price: $99.99", id: "text1")
        textIndex.append(text: "Unit Price: $49.99", id: "text2")
        textIndex.append(text: "Tax Amount: $5.00", id: "text3")
        textIndex.append(text: "Discount: 10%", id: "text4")
        
        let results = textIndex.contains("price")
        
        XCTAssertEqual(results.count, 2)
        print("Contains 'price':")
        for result in results {
            print("- \(result.text)")
        }
    }
    
    func testPrefixSearch() {
        textIndex.append(text: "apple.com", id: "text1")
        textIndex.append(text: "application", id: "text2")
        textIndex.append(text: "banana.com", id: "text3")
        
        let results = textIndex.hasPrefix("app")
        
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.contains(where: { $0.text == "apple.com" }))
        XCTAssertTrue(results.contains(where: { $0.text == "application" }))
    }
    
    func testSuffixSearch() {
        textIndex.append(text: "document.pdf", id: "text1")
        textIndex.append(text: "image.pdf", id: "text2")
        textIndex.append(text: "data.json", id: "text3")
        
        let results = textIndex.hasSuffix(".pdf")
        
        XCTAssertEqual(results.count, 2)
        print("Files ending with '.pdf':")
        for result in results {
            print("- \(result.text)")
        }
    }
    
    // MARK: - Update Operations Tests
    
    func testUpsert() {
        textIndex.append(text: "Original Text", id: "text1")
        XCTAssertEqual(textIndex.text(for: "text1"), "Original Text")
        
        // Upsert existing
        textIndex.upsert(text: "Updated Text", id: "text1")
        XCTAssertEqual(textIndex.text(for: "text1"), "Updated Text")
        XCTAssertEqual(textIndex.count, 1)
        
        // Upsert new
        textIndex.upsert(text: "New Text", id: "text2")
        XCTAssertEqual(textIndex.text(for: "text2"), "New Text")
        XCTAssertEqual(textIndex.count, 2)
    }
    
    func testUpdate() {
        textIndex.append(text: "Old Text", id: "text1")
        
        let success = textIndex.update(text: "New Text", id: "text1")
        XCTAssertTrue(success)
        XCTAssertEqual(textIndex.text(for: "text1"), "New Text")
        
        let failure = textIndex.update(text: "Some Text", id: "nonexistent")
        XCTAssertFalse(failure)
    }
    
    func testRemove() {
        textIndex.append(text: "Text 1", id: "text1")
        textIndex.append(text: "Text 2", id: "text2")
        textIndex.append(text: "Text 3", id: "text3")
        
        XCTAssertEqual(textIndex.count, 3)
        
        let success = textIndex.remove("text2")
        XCTAssertTrue(success)
        XCTAssertEqual(textIndex.count, 2)
        XCTAssertFalse(textIndex.contains(id: "text2"))
        
        let failure = textIndex.remove("nonexistent")
        XCTAssertFalse(failure)
    }
    
    func testRemoveAll() {
        textIndex.append(text: ["Text 1", "Text 2", "Text 3"], 
                        id: ["text1", "text2", "text3"])
        
        XCTAssertEqual(textIndex.count, 3)
        
        textIndex.removeAll()
        
        XCTAssertEqual(textIndex.count, 0)
        XCTAssertTrue(textIndex.allIDs().isEmpty)
        XCTAssertTrue(textIndex.allTexts().isEmpty)
    }
    
    // MARK: - Batch Operations Tests
    
    func testBatchAppend() {
        let texts = ["Text 1", "Text 2", "Text 3"]
        let ids = ["id1", "id2", "id3"]
        
        textIndex.append(text: texts, id: ids)
        
        XCTAssertEqual(textIndex.count, 3)
        XCTAssertEqual(textIndex.text(for: "id2"), "Text 2")
    }
    
    func testBatchRemove() {
        textIndex.append(text: ["Text 1", "Text 2", "Text 3", "Text 4"], 
                        id: ["id1", "id2", "id3", "id4"])
        
        let success = textIndex.remove(["id2", "id4"])
        XCTAssertTrue(success)
        XCTAssertEqual(textIndex.count, 2)
        XCTAssertTrue(textIndex.contains(id: "id1"))
        XCTAssertTrue(textIndex.contains(id: "id3"))
    }
    
    // MARK: - Real-world OCR Scenario Tests
    
    func testOCRReceiptScenario() {
        // 模拟从收据图片中识别的文本块
        textIndex.append(text: "Store Name: Apple Store", id: "line1")
        textIndex.append(text: "Address: 123 Main St", id: "line2")
        textIndex.append(text: "Date: 2024-01-15", id: "line3")
        textIndex.append(text: "iPhone 15 Pro", id: "line4")
        textIndex.append(text: "Price: $999.00", id: "line5")
        textIndex.append(text: "Tax: $79.92", id: "line6")
        textIndex.append(text: "Total: $1,078.92", id: "line7")
        
        // 搜索价格相关信息
        let priceResults = textIndex.contains("price")
        XCTAssertGreaterThan(priceResults.count, 0)
        print("\nPrice-related text blocks:")
        for result in priceResults {
            print("- \(result.text)")
        }
        
        // 搜索总额
        let totalResults = textIndex.contains("total")
        XCTAssertEqual(totalResults.count, 1)
        XCTAssertEqual(totalResults.first?.text, "Total: $1,078.92")
        
        // 搜索商品
        let productResults = textIndex.query("iPhone 15")
        let topProduct = textIndex.topK("iPhone 15", k: 1)
        XCTAssertGreaterThan(topProduct.first?.score ?? 0, 0.5)
        print("\nTop product match for 'iPhone 15': \(topProduct.first?.text ?? "none")")
    }
    
    func testOCRBusinessCardScenario() {
        // 模拟从名片图片中识别的文本块
        textIndex.append(text: "John Smith", id: "name")
        textIndex.append(text: "Senior Software Engineer", id: "title")
        textIndex.append(text: "Apple Inc.", id: "company")
        textIndex.append(text: "john.smith@apple.com", id: "email")
        textIndex.append(text: "+1 (555) 123-4567", id: "phone")
        
        // 搜索邮箱
        let emailResults = textIndex.hasSuffix("@apple.com")
        XCTAssertEqual(emailResults.count, 1)
        print("\nEmail: \(emailResults.first?.text ?? "none")")
        
        // 搜索职位
        let titleResults = textIndex.contains("engineer")
        XCTAssertEqual(titleResults.count, 1)
        print("Title: \(titleResults.first?.text ?? "none")")
        
        // 模糊搜索名字
        let nameResults = textIndex.topK("john", k: 3)
        XCTAssertGreaterThan(nameResults.first?.score ?? 0, 0)
        print("Name search results for 'john':")
        for result in nameResults {
            print("- \(result.text) (score: \(result.score))")
        }
    }
    
    func testChineseTextSearch() {
        // 测试中文文本搜索
        textIndex.append(text: "苹果公司", id: "text1")
        textIndex.append(text: "苹果手机", id: "text2")
        textIndex.append(text: "华为手机", id: "text3")
        textIndex.append(text: "小米电视", id: "text4")
        
        // 搜索 "苹果"
        let appleResults = textIndex.contains("苹果")
        XCTAssertEqual(appleResults.count, 2)
        print("\nChinese search for '苹果':")
        for result in appleResults {
            print("- \(result.text)")
        }
        
        // 搜索 "手机"
        let phoneResults = textIndex.contains("手机")
        XCTAssertEqual(phoneResults.count, 2)
        print("\nChinese search for '手机':")
        for result in phoneResults {
            print("- \(result.text)")
        }
        
        // 相似度搜索
        let similarResults = textIndex.topK("苹果", k: 2)
        print("\nTop 2 similar results for '苹果':")
        for (index, result) in similarResults.enumerated() {
            print("\(index + 1). \(result.text) - Score: \(result.score)")
        }
    }
    
    func testQueryWithIDs() {
        textIndex.append(text: "Apple", id: "text1")
        textIndex.append(text: "Application", id: "text2")
        textIndex.append(text: "Banana", id: "text3")
        
        let results = textIndex.queryWithIDs("App")
        
        XCTAssertEqual(results.count, 3)
        // 应该能找到包含 "App" 的文本并按相似度排序
        let sortedResults = results.sorted(by: { $0.score > $1.score })
        print("\nAll results for 'App' with scores:")
        for result in sortedResults {
            print("- \(result.text) (ID: \(result.id), Score: \(result.score))")
        }
    }
}
