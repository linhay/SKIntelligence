import Foundation
import SKIACP
import SKIJSONRPC

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

    private static func canonicalJSONString(_ value: JSONValue) -> String {
        switch value {
        case .null:
            return "null"
        case .bool(let v):
            return v ? "true" : "false"
        case .number(let v):
            return String(v)
        case .string(let v):
            return "\"\(v.replacingOccurrences(of: "\"", with: "\\\""))\""
        case .array(let values):
            return "[\(values.map(canonicalJSONString).joined(separator: ","))]"
        case .object(let object):
            let pairs = object.keys.sorted().map { key in
                "\"\(key.replacingOccurrences(of: "\"", with: "\\\""))\":\(canonicalJSONString(object[key] ?? .null))"
            }
            return "{\(pairs.joined(separator: ","))}"
        }
    }
}
