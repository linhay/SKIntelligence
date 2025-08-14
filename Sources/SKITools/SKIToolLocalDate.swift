//
//  SKIDateTool.swift
//  SKIntelligence
//
//  Created by linhey on 6/14/25.
//

import Foundation
import SKIntelligence
import JSONSchemaBuilder

public struct SKIToolLocalDate: SKITool {

    @Schemable
    public struct Arguments {
        @SchemaOptions(.description("时间格式，例如 yyyy-MM-dd"))
        public let format: String?

        public init(format: String? = nil) {
            self.format = format
        }
    }

    @Schemable
    public struct ToolOutput: Codable {
        @SchemaOptions(.description("当前日期，格式为 yyyy-MM-dd"))
        public let date: String
        @SchemaOptions(.description("可能的错误信息"))
        public let error: String?

        public init(date: String, error: String? = nil) {
            self.date = date
            self.error = error
        }
    }

    public var name: String = "getCurrentDate"
    public var description: String = "返回当前日期，格式为 yyyy-MM-dd。"
    
    public init() {}

    public func call(_ arguments: Arguments) async throws -> ToolOutput {
        let formatter = DateFormatter()
        formatter.dateFormat = arguments.format ?? "yyyy-MM-dd"
        let currentDate = formatter.string(from: Date())
        return ToolOutput(date: currentDate)
    }
}
