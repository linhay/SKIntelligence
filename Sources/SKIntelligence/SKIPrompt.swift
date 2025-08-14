//
//  SKIPrompt.swift
//  SKIntelligence
//
//  Created by linhey on 6/13/25.
//

import Foundation

public struct SKIPrompt: ExpressibleByStringLiteral {
    
    public let value: String

    // MARK: - String Literal Conformance
    public  init(stringLiteral value: StringLiteralType) {
        self.value = value
    }

    // MARK: - Builder
    @resultBuilder
    public struct Builder {
        public static func buildBlock(_ components: String...) -> String {
            components.joined(separator: "\n")
        }

        public static func buildOptional(_ component: String?) -> String {
            component ?? ""
        }

        public static func buildEither(first component: String) -> String {
            component
        }

        public static func buildEither(second component: String) -> String {
            component
        }

        public static func buildArray(_ components: [String]) -> String {
            components.joined(separator: "\n")
        }

        public static func buildExpression(_ expression: String) -> String {
            expression
        }

        public static func buildExpression(_ expression: SKIPrompt) -> String {
            expression.value
        }

        public static func buildLimitedAvailability(_ component: String) -> String {
            component
        }
    }

    // MARK: - Init with Builder
    public init(@Builder _ content: () -> String) {
        self.value = content()
    }
}
