import Foundation
import SKIACP
import SKIACP
@preconcurrency import STJSON

public struct ACPToolCallFingerprint: Hashable, Sendable {
    public let value: String

    public init(_ request: ACPSessionPermissionRequestParams) {
        self.value = Self.makeValue(request.toolCall)
    }

    private static func makeValue(_ toolCall: ACPToolCallUpdate) -> String {
        let kind = toolCall.kind?.rawValue ?? ""
        let title = toolCall.title ?? ""
        let locations = (toolCall.locations ?? [])
            .map { "\($0.path):\($0.line ?? 0)" }
            .sorted()
            .joined(separator: "|")
        let rawInput = toolCall.rawInput.map(canonicalJSONString) ?? ""
        return [kind, title, locations, rawInput].joined(separator: "##")
    }

    private static func canonicalJSONString(_ value: AnyCodable) -> String {
        if let object = try? value.decode(to: [String: AnyCodable].self) {
            let pairs = object.keys.sorted().map { key in
                "\"\(key.replacingOccurrences(of: "\"", with: "\\\""))\":\(canonicalJSONString(object[key] ?? AnyCodable(nil as String?)))"
            }
            return "{\(pairs.joined(separator: ","))}"
        }
        if let array = try? value.decode(to: [AnyCodable].self) {
            return "[\(array.map(canonicalJSONString).joined(separator: ","))]"
        }
        if let string = value.value as? String {
            return "\"\(string.replacingOccurrences(of: "\"", with: "\\\""))\""
        }
        if let bool = value.value as? Bool {
            return bool ? "true" : "false"
        }
        if let number = number(from: value.value) {
            return String(number)
        }
        if value.value is Void {
            return "null"
        }
        return "null"
    }

    private static func number(from raw: Any) -> Double? {
        switch raw {
        case let value as Double: return value
        case let value as Float: return Double(value)
        case let value as Int: return Double(value)
        case let value as Int8: return Double(value)
        case let value as Int16: return Double(value)
        case let value as Int32: return Double(value)
        case let value as Int64: return Double(value)
        case let value as UInt: return Double(value)
        case let value as UInt8: return Double(value)
        case let value as UInt16: return Double(value)
        case let value as UInt32: return Double(value)
        case let value as UInt64: return Double(value)
        default: return nil
        }
    }
}
