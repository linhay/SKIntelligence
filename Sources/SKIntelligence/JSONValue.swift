//
//  JSONValue+Extensions.swift
//  SKIntelligence
//
//  Created by ktiays on 2025/2/25.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import Foundation
import JSONSchema

// MARK: - JSONValue Conversion

public extension [String: JSONValue] {
    /// Converts JSONValue dictionary to untyped [String: Any] dictionary
    var untypedDictionary: [String: Any] {
        mapValues { $0.toAny() }
    }
}

private extension JSONValue {
    /// Recursively converts JSONValue to Any type
    func toAny() -> Any {
        switch self {
        case .null:
            return NSNull()
        case .boolean(let v):
            return v
        case .integer(let v):
            return v
        case .number(let v):
            return v
        case .string(let v):
            return v
        case .array(let arr):
            return arr.map { $0.toAny() }
        case .object(let dict):
            return dict.mapValues { $0.toAny() }
        }
    }
}


