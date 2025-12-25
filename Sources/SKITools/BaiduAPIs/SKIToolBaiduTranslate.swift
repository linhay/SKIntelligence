//
//  File.swift
//
//
//  Created by linhey on 2024/4/7.
//

import Crypto
import Foundation
import HTTPTypes
import HTTPTypesFoundation
import JSONSchemaBuilder
import SKIntelligence
import STJSON

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

public struct SKIToolBaiduTranslate: SKITool {

    public let name: String = "baidu-translate"
    public let description: String = "Translate text using Baidu Translate API."

    @Schemable
    public struct Arguments: Codable, Sendable {

        @SchemaOptions(.description("The text to be translated."))
        public var q: String
        @SchemaOptions(.description("The source language of the text."))
        public var from: HumanLangeuage
        @SchemaOptions(.description("The target language for the translation."))
        public var to: HumanLangeuage
        /// [仅开通了TTS者需填写] 是否显示语音合成资源 tts=0显示，tts=1不显示
        @SchemaOptions(
            .description("Whether to enable text-to-speech. tts=0 shows, tts=1 does not show."))
        public var tts: Bool?
        /// [仅开通了词典者需填写] 是否显示词典资源 dict=0显示，dict=1不显示
        @SchemaOptions(
            .description(
                "Whether to enable dictionary resources. dict=0 shows, dict=1 does not show."))
        public var dict: Bool?
        /// [仅开通“我的术语库”用户需填写] 判断是否需要使用自定义术语干预API, 1-是，0-否
        @SchemaOptions(
            .description("Whether to use custom terminology intervention API. 1-Yes, 0-No."))
        public var action: Bool?

        public init(
            q: String,
            from: HumanLangeuage,
            to: HumanLangeuage,
            tts: Bool? = nil,
            dict: Bool? = nil,
            action: Bool? = nil
        ) {
            self.q = q
            self.from = from
            self.to = to
            self.tts = tts
            self.dict = dict
            self.action = action
        }

        var toQueries: [String: String] {
            var dict = [String: String]()
            dict["q"] = q
            dict["from"] = from.rawValue
            dict["to"] = to.rawValue
            dict["tts"] = tts.flatMap({ $0 ? "1" : "0" })
            dict["dict"] = self.dict.flatMap({ $0 ? "1" : "0" })
            dict["action"] = action.flatMap({ $0 ? "1" : "0" })
            return dict
        }

        public func sign(_ service: SKIBaiduAuthentication) -> [String: String] {
            let sign = signParameter(service)
            return self.toQueries.merging(sign.toQueries, uniquingKeysWith: { $1 })
        }

        public func signParameter(_ service: SKIBaiduAuthentication) -> BaiduTranslateSignParameter
        {
            let salt = BaiduTranslateSignParameter.salt
            guard
                let data =
                    (service.appID
                    + q
                    + salt
                    + service.appKey).data(using: .utf8)
            else {
                return .init(sign: "", salt: "", appid: service.appID)
            }
            let sign = Insecure.MD5.hash(data: data).map {
                String(format: "%02hhx", $0)
            }.joined()
            return BaiduTranslateSignParameter.init(sign: sign, salt: salt, appid: service.appID)
        }

    }

    public struct TranslateResult: Codable {
        public let src: String
        public let dst: String
        public let src_tts: String?
        public let dst_tts: String?
        public let dict: [String: AnyCodable]?
    }

    public struct ToolOutput: Codable, @unchecked Sendable {
        public let from: String
        public let to: String
        public let trans_result: [TranslateResult]
    }

    enum Errors: Error {
        case invalidURL
    }

    public let authentication: SKIBaiduAuthentication

    public init(authentication: SKIBaiduAuthentication) {
        self.authentication = authentication
    }

    public func call(_ arguments: Arguments) async throws -> ToolOutput {
        var components = URLComponents(
            url: URL(string: authentication.host)!, resolvingAgainstBaseURL: true)
        components?.path = "/api/trans/vip/translate"
        if components?.queryItems == nil {
            components?.queryItems = []
        }

        for (key, value) in arguments.sign(authentication) {
            components?.queryItems?.append(.init(name: key, value: value))
        }

        guard let url = components?.url else {
            throw Errors.invalidURL
        }

        let request = HTTPRequest(method: .get, url: url)
        let (data, _) = try await URLSession.tools.data(for: request)

        if let error = try? JSONDecoder().decode(BaiduTranslate.ErrorResponse.self, from: data) {
            throw error
        }
        return try JSONDecoder().decode(ToolOutput.self, from: data)
    }

}
