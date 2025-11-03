# SKITextIndex 使用指南

`SKITextIndex` 是一个专门用于文本块搜索的索引结构，特别适合用于图片中识别出的文本（OCR）搜索场景。

## 主要特性

- ✅ **相似度搜索**: 使用 Jaccard 相似度和最长公共子序列算法
- ✅ **精确匹配**: 不区分大小写的精确文本匹配
- ✅ **包含搜索**: 查找包含指定文本的所有条目
- ✅ **前缀/后缀搜索**: 快速查找以特定文本开头或结尾的条目
- ✅ **中文支持**: 内置字符级 n-gram，支持中文等无空格分词语言
- ✅ **批量操作**: 支持批量添加、更新、删除
- ✅ **高效索引**: O(1) 查找，快速更新和删除

## 基本用法

### 1. 创建索引并添加文本

```swift
import SKIClip

// 创建文本索引
let textIndex = SKITextIndex<String>()

// 添加单个文本块
textIndex.append(text: "Apple iPhone 15 Pro", id: "text1")
textIndex.append(text: "Samsung Galaxy S24", id: "text2")
textIndex.append(text: "MacBook Pro 16-inch", id: "text3")

// 批量添加
let texts = ["Text 1", "Text 2", "Text 3"]
let ids = ["id1", "id2", "id3"]
textIndex.append(text: texts, id: ids)
```

### 2. 相似度搜索

```swift
// 查询并获取所有相似度分数
let scores = textIndex.query("iPhone 15")

// 获取前 K 个最相似的结果
let topResults = textIndex.topK("iPhone 15", k: 3)
for result in topResults {
    print("\(result.text) - Score: \(result.score)")
}
// 输出:
// iPhone 15 Pro - Score: 0.90384614
// iPhone 15 Pro Max - Score: 0.8794118
// iPhone 14 - Score: 0.7916666

// 获取所有结果及其 ID 和分数
let allResults = textIndex.queryWithIDs("iPhone")
for result in allResults {
    print("ID: \(result.id), Text: \(result.text), Score: \(result.score)")
}
```

### 3. 精确匹配和包含搜索

```swift
// 精确匹配（不区分大小写）
let exactMatches = textIndex.exactMatch("hello world")

// 包含搜索
let containsResults = textIndex.contains("price")
for result in containsResults {
    print(result.text)
}
// 输出: Total Price: $99.99, Unit Price: $49.99

// 前缀搜索
let prefixResults = textIndex.hasPrefix("app")
// 匹配: "apple.com", "application"

// 后缀搜索
let suffixResults = textIndex.hasSuffix(".pdf")
// 匹配: "document.pdf", "image.pdf"
```

### 4. 更新和删除操作

```swift
// 更新已存在的文本
textIndex.update(text: "New Text", id: "text1")

// 插入或更新（如果存在则更新，否则插入）
textIndex.upsert(text: "Updated Text", id: "text1")

// 删除单个条目
textIndex.remove("text1")

// 批量删除
textIndex.remove(["id1", "id2", "id3"])

// 清空所有数据
textIndex.removeAll()
```

### 5. 查询索引信息

```swift
// 获取索引中的条目数量
let count = textIndex.count

// 检查 ID 是否存在
if textIndex.contains(id: "text1") {
    print("Text exists")
}

// 根据 ID 获取文本
if let text = textIndex.text(for: "text1") {
    print("Text: \(text)")
}

// 获取所有 ID
let allIDs = textIndex.allIDs()

// 获取所有文本
let allTexts = textIndex.allTexts()
```

## 实际应用场景

### 场景 1: OCR 收据识别

```swift
let receiptIndex = SKITextIndex<String>()

// 从收据图片中识别的文本块
receiptIndex.append(text: "Store Name: Apple Store", id: "line1")
receiptIndex.append(text: "Address: 123 Main St", id: "line2")
receiptIndex.append(text: "Date: 2024-01-15", id: "line3")
receiptIndex.append(text: "iPhone 15 Pro", id: "line4")
receiptIndex.append(text: "Price: $999.00", id: "line5")
receiptIndex.append(text: "Tax: $79.92", id: "line6")
receiptIndex.append(text: "Total: $1,078.92", id: "line7")

// 搜索价格相关信息
let priceInfo = receiptIndex.contains("price")
// 结果: "Price: $999.00"

// 搜索总额
let totalInfo = receiptIndex.contains("total")
// 结果: "Total: $1,078.92"

// 搜索商品
let products = receiptIndex.topK("iPhone 15", k: 1)
// 结果: "iPhone 15 Pro" with high score
```

### 场景 2: OCR 名片识别

```swift
let businessCardIndex = SKITextIndex<String>()

// 从名片图片中识别的文本块
businessCardIndex.append(text: "John Smith", id: "name")
businessCardIndex.append(text: "Senior Software Engineer", id: "title")
businessCardIndex.append(text: "Apple Inc.", id: "company")
businessCardIndex.append(text: "john.smith@apple.com", id: "email")
businessCardIndex.append(text: "+1 (555) 123-4567", id: "phone")

// 搜索邮箱
let emails = businessCardIndex.hasSuffix("@apple.com")
// 结果: "john.smith@apple.com"

// 搜索职位
let titles = businessCardIndex.contains("engineer")
// 结果: "Senior Software Engineer"

// 模糊搜索名字
let names = businessCardIndex.topK("john", k: 1)
// 结果: "John Smith" with high score
```

### 场景 3: 中文文本搜索

```swift
let chineseIndex = SKITextIndex<String>()

// 添加中文文本
chineseIndex.append(text: "苹果公司", id: "text1")
chineseIndex.append(text: "苹果手机", id: "text2")
chineseIndex.append(text: "华为手机", id: "text3")
chineseIndex.append(text: "小米电视", id: "text4")

// 搜索 "苹果"
let appleResults = chineseIndex.contains("苹果")
// 结果: ["苹果公司", "苹果手机"]

// 搜索 "手机"
let phoneResults = chineseIndex.contains("手机")
// 结果: ["苹果手机", "华为手机"]

// 相似度搜索
let similarResults = chineseIndex.topK("苹果", k: 2)
// 结果:
// 1. 苹果公司 - Score: 0.875
// 2. 苹果手机 - Score: 0.875
```

## 相似度算法

`SKITextIndex` 使用多层相似度计算：

1. **精确匹配**: 分数 = 1.0
2. **包含关系**:
   - 目标包含查询: 0.8 - 0.95（基于长度比例）
   - 查询包含目标: 0.7 - 0.85（基于长度比例）
3. **Token 相似度**: Jaccard 系数（交集/并集）× 0.7
4. **字符串相似度**: LCS 比率（最长公共子序列/最大长度）× 0.3

## 性能特点

- **空间复杂度**: O(n) - n 为文本条目数量
- **查询时间**: O(n × m) - n 为索引大小，m 为平均文本长度
- **更新时间**: O(m) - m 为文本长度
- **删除时间**: O(1) - 使用交换技巧

## 与 SKISimilarityIndex 的对比

| 特性 | SKISimilarityIndex | SKITextIndex |
|------|-------------------|--------------|
| 数据类型 | Float 向量 | 文本字符串 |
| 相似度算法 | 余弦相似度 | Jaccard + LCS |
| 加速 | BLAS 矩阵运算 | 字符串算法 |
| 用途 | 图像/嵌入向量搜索 | OCR 文本搜索 |
| 精确匹配 | ❌ | ✅ |
| 包含搜索 | ❌ | ✅ |
| 前缀/后缀搜索 | ❌ | ✅ |

## 注意事项

1. 文本索引对大小写不敏感
2. 自动处理变音符号（diacritics）
3. 支持中文等无空格分词语言的 n-gram 分词
4. ID 必须唯一，重复添加会触发 `precondition` 失败
5. 更新和删除不存在的 ID 会返回 `false`

## 最佳实践

1. **选择合适的 ID 类型**: 使用 `String`、`UUID` 或 `Int` 作为 ID
2. **批量操作**: 尽量使用批量添加方法提高效率
3. **定期清理**: 对于不再需要的条目及时删除
4. **组合搜索**: 先用 `contains` 或 `hasPrefix` 快速过滤，再用 `topK` 获取最佳匹配
5. **分数阈值**: 根据实际需求设置相似度分数阈值（通常 > 0.5 为相关）

## 示例：完整的 OCR 搜索流程

```swift
import SKIClip

// 1. 创建索引
let ocrIndex = SKITextIndex<UUID>()

// 2. 从 OCR 结果添加文本块
let ocrResults = [
    ("Apple Store", UUID()),
    ("iPhone 15 Pro", UUID()),
    ("Price: $999.00", UUID()),
    ("Total: $1,078.92", UUID())
]

for (text, id) in ocrResults {
    ocrIndex.append(text: text, id: id)
}

// 3. 执行搜索
let searchQuery = "iPhone"
let results = ocrIndex.topK(searchQuery, k: 5)

// 4. 过滤和处理结果
let relevantResults = results.filter { $0.score > 0.5 }
for result in relevantResults {
    print("Found: \(result.text)")
    print("Score: \(result.score)")
    print("ID: \(result.id)")
    print("---")
}
```

## 总结

`SKITextIndex` 是一个专门为 OCR 文本搜索设计的高效索引结构，提供了丰富的搜索功能和良好的性能表现。它与 `SKISimilarityIndex` 互补，共同构成了完整的相似度搜索解决方案。
