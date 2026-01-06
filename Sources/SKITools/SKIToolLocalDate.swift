//
//  SKIDateTool.swift
//  SKIntelligence
//
//  Created by linhey on 6/14/25.
//

import Foundation
import JSONSchemaBuilder
import SKIntelligence

public struct SKIToolLocalDate: SKITool {

    @Schemable
    public struct Arguments {
        @SchemaOptions(.description("日期时间格式，例如 'yyyy-MM-dd' 或 'yyyy-MM-dd HH:mm:ss'"))
        public let format: String?

        public init(format: String? = nil) {
            self.format = format
        }
    }

    @Schemable
    public struct ToolOutput: Codable {
        @SchemaOptions(.description("当前日期时间字符串"))
        public let date: String
        @SchemaOptions(.description("可能的错误信息"))
        public let error: String?

        public init(date: String, error: String? = nil) {
            self.date = date
            self.error = error
        }
    }

    public var name: String = "getCurrentDateTime"
    public var description: String =
        "获取当前日期和时间。支持自定义格式（默认为 yyyy-MM-dd）。例如：如果要获取具体时间，可以使用 'HH:mm:ss' 或 'yyyy-MM-dd HH:mm:ss'。"

    public func displayName(for arguments: Arguments) async -> String {
        if let format = arguments.format {
            return "查询时间 [\(format)]"
        }
        return "查询当前时间"
    }

    public init() {}

    public func call(_ arguments: Arguments) async throws -> ToolOutput {
        let formatter = DateFormatter()
        formatter.dateFormat = arguments.format ?? "yyyy-MM-dd"
        let currentDate = formatter.string(from: Date())
        return ToolOutput(date: currentDate)
    }
}
