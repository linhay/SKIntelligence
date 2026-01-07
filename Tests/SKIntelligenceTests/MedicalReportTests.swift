//
//  MedicalReportTests.swift
//  SKIntelligence
//
//  Created by linhey on 2025.
//

import Testing
import Foundation
import SKIntelligence
import SKIClients

#if !os(Linux)

/// 医疗报告识别测试用例
/// Medical Report Recognition Test Cases
@Suite("Medical Report Recognition")
struct MedicalReportTests {
    
    // MARK: - Test: Medical Report Image Analysis
    let imageURL = URL(string: "https://img1p.dxycdn.com/p/s115/2025/1022/933/8212768101915001891.jpg%21q70?Expires=1766569966&OSSAccessKeyId=LTAI5t8gdqA59d55WCEDtWsJ&Signature=WWSuDHoN7UeyhiTy%2FidyGodTs4Q%3D")
    
    // 配置客户端
    let client = OpenAIClient()
        .model("google/gemma-3-27b-it:free")
        .model("qwen/qwen-2.5-vl-7b-instruct:free")
        .model("nvidia/nemotron-nano-12b-v2-vl:free")
        .token(Keys.openrouter)
        .url(.openrouter)
//        .model(.gemini_2_5_flash)
//        .token(Keys.google)
//        .url(.gemini)
    
    private var transcript: SKITranscript {
        get async {
            let transcript = SKITranscript()
            await transcript.setObserveNewEntry(.print())
            return transcript
        }
    }
    
    /// 测试使用图片URL进行医疗报告识别
    @Test("Analyze medical report from image URL")
    func analyzeReportFromURL() async throws {
        let session = await SKILanguageModelSession(
            client: client,
            transcript: transcript
        )
        
        // 使用公开可用的血常规报告样例图片
        // Sample CBC (Complete Blood Count) report image
        guard let imageURL = imageURL else {
            Issue.record("Invalid image URL")
            return
        }
        
        let prompt = SKIPrompt(
            text: """
            请分析这张医疗报告图片，提取以下信息：
            1. 报告类型（如：血常规、尿常规、生化检查等）
            2. 检测日期
            3. 检测机构
            4. 主要指标及其数值/英文名/单位/参考区间
            5. 异常指标（标注高/低）
            
            请以结构化的JSON格式返回结果。
            """,
            images: [imageURL],
            imageDetail: .high
        )
        
        let response = try await session.respond(to: prompt)
        print("Medical Report Analysis Result:")
        print(response)
        
        // 验证响应不为空
        #expect(!response.isEmpty)
    }
    
    // MARK: - Test: Medical Report from Base64 Data
    
    /// 测试使用Base64编码的图片数据进行医疗报告识别
    @Test("Analyze medical report from image data")
    func analyzeReportFromData() async throws {
        
        let session = await SKILanguageModelSession(
            client: client,
            transcript: transcript
        )
        

        guard let imageURL = imageURL,
              let imageData = try? Data(contentsOf: imageURL) else {
            Issue.record("Failed to load image data from URL")
            return
        }
        
        let prompt = SKIPrompt(
            text: "请描述这张图片的内容。",
            imageData: [(data: imageData, mimeType: "image/png")],
            imageDetail: .auto
        )
        
        let response = try await session.respond(to: prompt)
        print("Medical Report Analysis Result:")
        print(response)
        
        // 验证响应不为空
        #expect(!response.isEmpty)
    }
        
    // MARK: - Test: SKIPrompt Image Helpers
    
    /// 测试SKIPrompt的图片辅助方法
    @Test("SKIPrompt image helper methods")
    func testImageHelpers() throws {
        // 测试imageDataURL方法
        let testData = Data([0x89, 0x50, 0x4E, 0x47]) // PNG magic bytes
        let dataURL = SKIPrompt.imageDataURL(from: testData, mimeType: "image/png")
        
        #expect(dataURL != nil)
        #expect(dataURL?.absoluteString.hasPrefix("data:image/png;base64,") == true)
        
        // 测试不同MIME类型
        let jpegURL = SKIPrompt.imageDataURL(from: testData, mimeType: "image/jpeg")
        #expect(jpegURL?.absoluteString.hasPrefix("data:image/jpeg;base64,") == true)
    }
}

#endif
