import Foundation

public enum ACPCLIOutputFormatter {
    public static func sessionUpdateJSON(
        sessionId: String,
        update: String,
        text: String
    ) throws -> String {
        let payload = SessionUpdatePayload(
            type: "session_update",
            sessionId: sessionId,
            update: update,
            text: text
        )
        return try encode(payload)
    }

    public static func promptResultJSON(
        sessionId: String,
        stopReason: String
    ) throws -> String {
        let payload = PromptResultPayload(type: "prompt_result", sessionId: sessionId, stopReason: stopReason)
        return try encode(payload)
    }

    public static func sessionStopJSON(sessionId: String) throws -> String {
        let payload = SessionStopPayload(type: "session_stop", sessionId: sessionId)
        return try encode(payload)
    }
}

private extension ACPCLIOutputFormatter {
    struct SessionUpdatePayload: Encodable {
        let type: String
        let sessionId: String
        let update: String
        let text: String
    }

    struct PromptResultPayload: Encodable {
        let type: String
        let sessionId: String
        let stopReason: String
    }

    struct SessionStopPayload: Encodable {
        let type: String
        let sessionId: String
    }

    static func encode<T: Encodable>(_ payload: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)
        return String(decoding: data, as: UTF8.self)
    }
}
