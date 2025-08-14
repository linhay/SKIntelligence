//
//  Created by ktiays on 2025/2/25.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import Foundation
import JSONSchema

public extension [String: JSONValue] {
    var untypedDictionary: [String: Any] {
        convertToUntypedDictionary(self)
    }
}

private func convertToUntyped(_ input: JSONValue) -> Any {
    switch input {
    case .null:
        NSNull()
    case let .boolean(bool):
        bool
    case let .integer(int):
        int
    case let .number(double):
        double
    case let .string(string):
        string
    case let .array(array):
        array.map { convertToUntyped($0) }
    case let .object(dictionary):
        convertToUntypedDictionary(dictionary)
    }
}

private func convertToUntypedDictionary(
    _ input: [String: JSONValue]
) -> [String: Any] {
    input.mapValues { v in
        switch v {
        case .null:
            NSNull()
        case let .boolean(bool):
            bool
        case let .integer(int):
            int
        case let .number(double):
            double
        case let .string(string):
            string
        case let .array(array):
            array.map { convertToUntyped($0) }
        case let .object(dictionary):
            convertToUntypedDictionary(dictionary)
        }
    }
}

extension JSONValue: ExpressibleByNilLiteral {
    public init(nilLiteral _: ()) {
        self = .null
    }
}

extension JSONValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: BooleanLiteralType) {
        self = .boolean(value)
    }
}

extension JSONValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: IntegerLiteralType) {
        self = .integer(value)
    }
}

extension JSONValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: FloatLiteralType) {
        self = .number(value)
    }
}

extension JSONValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: StringLiteralType) {
        self = .string(value)
    }
}

extension JSONValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: JSONValue...) {
        self = .array(elements)
    }
}

extension JSONValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(.init(uniqueKeysWithValues: elements))
    }
}
