////
////  File.swift
////  
////
////  Created by linhey on 2024/4/7.
////
//
//import Foundation
//
//public struct BaiduTranslateAPIs {
//    
//    public let client: LLMClientProtocol
//    public let serivce: BaiduTranslateService
//    
//    public init(client: LLMClientProtocol, serivce: BaiduTranslateService) {
//        self.client = client
//        self.serivce = serivce
//    }
//    
//}
//
//public extension BaiduTranslateAPIs {
//    
//    /// 领域翻译
//    func fieldtranslate(_ parameter: BaiduTranslate.FieldTranslateParameter) async throws -> BaiduTranslate.TranslateResponse {
//        var request = client.request(of: serivce, path: "api/trans/vip/fieldtranslate")
//        request = client.add(queries: parameter.sign(serivce), to: request)
//        let response = try await client.data(for: request)
//        if let error: BaiduTranslate.ErrorResponse = try? client.decode(response.data) {
//            throw error
//        }
//        return try client.decode(response.data)
//    }
//
//    /// 语种识别
//    func language(_ parameter: BaiduTranslate.LanguageParameter) async throws -> BaiduTranslate.LanguageResponse {
//        var request = client.request(of: serivce, path: "api/trans/vip/language")
//        request = client.add(queries: parameter.sign(serivce), to: request)
//        let response = try await client.data(for: request)
//        if let error: BaiduTranslate.ErrorResponse = try? client.decode(response.data) {
//            throw error
//        }
//        return try client.decode(response.data)
//    }
//    
//}
