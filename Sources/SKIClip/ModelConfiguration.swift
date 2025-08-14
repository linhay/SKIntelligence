//
//  ModelConfiguration.swift
//  SKIntelligence
//
//  Created by linhey on 7/11/25.
//

import Foundation

public protocol ModelConfigurationProtocol {
    var name: String { get }
    var factory: () -> CLIPEncoder { get }
}

public extension ModelConfigurationProtocol {
 
    func eraseToCachedModelConfiguration() -> CachedModelConfiguration {
        if let cached = self as? CachedModelConfiguration {
            return cached
        } else {
            return CachedModelConfiguration(name: name, factory: factory)
        }
    }
    
}


public class CachedModelConfiguration: ModelConfigurationProtocol {
    
    public let name: String
    public private(set) var factory: () -> CLIPEncoder
    private var cache: CLIPEncoder?
    
    public init(name: String, factory: @escaping () -> CLIPEncoder) {
        self.name = name
        self.factory = factory
        
        self.factory = { [weak self] in
            guard let self = self else { return factory() }
            if let cache {
                return cache
            }
            
            let model = factory()
            self.cache = model
            return model
        }
    }
    
}

public struct ModelConfiguration: ModelConfigurationProtocol {
    
    public let name: String
    public let factory: () -> CLIPEncoder
    
    public init(name: String, factory: @escaping () -> CLIPEncoder) {
        self.name = name
        self.factory = factory
    }

}
