//
//  File.swift
//
//
//  Created by linhey on 2024/4/7.
//

import Foundation
import Crypto
import STJSON

//https://fanyi-api.baidu.com/api/trans/vip/translate

public struct BaiduTranslateSignParameter: Codable {
    public let sign: String
    public let salt: String
    public let appid: String
    public static var salt: String { (1000000000..<10000000000).randomElement()?.description ?? "salt" }
    
    var toQueries: [String: String] {
        var dict = [String: String]()
        dict["sign"] = sign
        dict["appid"] = appid
        dict["salt"] = salt
        return dict
    }
}

public struct BaiduTranslate { }

public extension BaiduTranslate {
        
    enum FieldTranslateDomain: String, Codable {
        /// 信息技术领域
        case it = "it"
        /// 金融财经领域
        case finance = "finance"
        /// 机械制造领域
        case machinery = "machinery"
        /// 生物医药领域
        case senimed = "senimed"
        /// 网络文学领域
        case novel = "novel"
        /// 学术论文领域
        case academic = "academic"
        /// 航空航天领域
        case aerospace = "aerospace"
        /// 人文社科领域
        case wiki = "wiki"
        /// 新闻资讯领域
        case news = "news"
        /// 法律法规领域
        case law = "law"
        /// 合同领域
        case contract = "contract"
    }
    
    struct FieldTranslateParameter: Codable {
        
        public var q: String
        public var from: HumanLangeuage
        public var to: HumanLangeuage
        /// 翻译领域类型
        public var domain: FieldTranslateDomain
        
        public init(q: String, from: HumanLangeuage, to: HumanLangeuage, domain: FieldTranslateDomain) {
            self.q = q
            self.from = from
            self.to = to
            self.domain = domain
        }
        
        var toQueries: [String: String] {
            var dict = [String: String]()
            dict["q"] = q
            dict["from"] = from.rawValue
            dict["to"] = to.rawValue
            dict["domain"] = domain.rawValue
            return dict
        }
        
        public func sign(_ service: SKIBaiduAuthentication) -> [String: String] {
            let sign = signParameter(service)
            return self.toQueries.merging(sign.toQueries, uniquingKeysWith: { $1 })
        }
        
        public func signParameter(_ service: SKIBaiduAuthentication) -> BaiduTranslateSignParameter {
            let salt = BaiduTranslateSignParameter.salt
            guard let data = (service.appID
                              + q
                              + salt
                              + domain.rawValue
                              + service.appKey).data(using: .utf8) else {
                return .init(sign: "", salt: "", appid: service.appID)
            }
            let sign = Insecure.MD5.hash(data: data).map {
                String(format: "%02hhx", $0)
            }.joined()
            return BaiduTranslateSignParameter.init(sign: sign, salt: salt, appid: service.appID)
        }
        
    }
    
    struct LanguageParameter: Codable {
        
        public var q: String
        
        public init(q: String) {
            self.q = q
        }
        
        var toQueries: [String: String] {
            var dict = [String: String]()
            dict["q"] = q
            return dict
        }
        
        public func sign(_ service: SKIBaiduAuthentication) -> [String: String] {
            let sign = signParameter(service)
            return self.toQueries.merging(sign.toQueries, uniquingKeysWith: { $1 })
        }
        
        public func signParameter(_ service: SKIBaiduAuthentication) -> BaiduTranslateSignParameter {
            let salt = BaiduTranslateSignParameter.salt
            guard let data = (service.appID
                              + q
                              + salt
                              + service.appKey).data(using: .utf8) else {
                return .init(sign: "", salt: "", appid: service.appID)
            }
            let sign = Insecure.MD5.hash(data: data).map {
                String(format: "%02hhx", $0)
            }.joined()
            return BaiduTranslateSignParameter.init(sign: sign, salt: salt, appid: service.appID)
        }
        
    }
    
}

public extension BaiduTranslate {
    
    struct ErrorResponse: Codable, LocalizedError {
        public let error_code: String
        public let error_msg: String
    }
    
    struct LanguageData: Codable {
        public let src: HumanLangeuage
    }
    
    struct LanguageResponse: Codable {
        public let data: LanguageData
    }
    
}
