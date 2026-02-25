//
//  BaiduTranslateAuthentication.swift
//  SKIntelligence
//
//  Created by linhey on 7/12/25.
//


public struct SKIBaiduAuthentication: Sendable {
        
    public var host: String
    public var appID: String
    public var appKey: String
    
    public init(appID: String,
                appKey: String,
                host: String = "https://fanyi-api.baidu.com") {
        self.appID = appID
        self.appKey = appKey
        self.host = host
    }
    
}
