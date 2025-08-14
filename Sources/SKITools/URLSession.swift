//
//  File.swift
//  SKIntelligence
//
//  Created by linhey on 6/14/25.
//

import Foundation

public extension URLSession {
    
    static let tools = {
        let config = URLSessionConfiguration.default
        return URLSession(configuration: config)
    }()
    
}
