//
//  File.swift
//  SKIntelligence
//
//  Created by linhey on 6/14/25.
//

import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

extension URLSession {

    public static let tools = {
        let config = URLSessionConfiguration.default
        return URLSession(configuration: config)
    }()

}
