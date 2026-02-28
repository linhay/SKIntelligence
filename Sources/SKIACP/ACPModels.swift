import Foundation
@preconcurrency import STJSON

public enum ACPStopReason: String, Codable, Sendable {
    case endTurn = "end_turn"
    case maxTokens = "max_tokens"
    case maxTurnRequests = "max_turn_requests"
    case refusal
    case cancelled
}

public struct ACPImplementationInfo: Codable, Sendable, Equatable {
    public var name: String
    public var title: String?
    public var version: String

    public init(name: String, title: String? = nil, version: String) {
        self.name = name
        self.title = title
        self.version = version
    }
}

public struct ACPClientCapabilities: Codable, Sendable, Equatable {
    public struct FileSystem: Codable, Sendable, Equatable {
        public var readTextFile: Bool
        public var writeTextFile: Bool

        public init(readTextFile: Bool = false, writeTextFile: Bool = false) {
            self.readTextFile = readTextFile
            self.writeTextFile = writeTextFile
        }
    }

    public var fs: FileSystem
    public var terminal: Bool

    public init(fs: FileSystem = .init(), terminal: Bool = false) {
        self.fs = fs
        self.terminal = terminal
    }
}

public struct ACPPromptCapabilities: Codable, Sendable, Equatable {
    public var image: Bool
    public var audio: Bool
    public var embeddedContext: Bool

    public init(image: Bool = false, audio: Bool = false, embeddedContext: Bool = false) {
        self.image = image
        self.audio = audio
        self.embeddedContext = embeddedContext
    }
}

public struct ACPMCPCapabilities: Codable, Sendable, Equatable {
    public var http: Bool
    public var sse: Bool

    public init(http: Bool = false, sse: Bool = false) {
        self.http = http
        self.sse = sse
    }
}

public struct ACPAgentCapabilities: Codable, Sendable, Equatable {
    public var authCapabilities: ACPAuthCapabilities
    public var sessionCapabilities: ACPSessionCapabilities
    public var loadSession: Bool
    public var promptCapabilities: ACPPromptCapabilities
    public var mcpCapabilities: ACPMCPCapabilities

    public init(
        authCapabilities: ACPAuthCapabilities = .init(),
        sessionCapabilities: ACPSessionCapabilities = .init(),
        loadSession: Bool = false,
        promptCapabilities: ACPPromptCapabilities = .init(),
        mcpCapabilities: ACPMCPCapabilities = .init()
    ) {
        self.authCapabilities = authCapabilities
        self.sessionCapabilities = sessionCapabilities
        self.loadSession = loadSession
        self.promptCapabilities = promptCapabilities
        self.mcpCapabilities = mcpCapabilities
    }

    private enum CodingKeys: String, CodingKey {
        case authCapabilities
        case sessionCapabilities
        case loadSession
        case promptCapabilities
        case mcpCapabilities
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.authCapabilities = try container.decodeIfPresent(ACPAuthCapabilities.self, forKey: .authCapabilities) ?? .init()
        self.sessionCapabilities = try container.decodeIfPresent(ACPSessionCapabilities.self, forKey: .sessionCapabilities) ?? .init()
        self.loadSession = try container.decodeIfPresent(Bool.self, forKey: .loadSession) ?? false
        self.promptCapabilities = try container.decodeIfPresent(ACPPromptCapabilities.self, forKey: .promptCapabilities) ?? .init()
        self.mcpCapabilities = try container.decodeIfPresent(ACPMCPCapabilities.self, forKey: .mcpCapabilities) ?? .init()
    }
}

public struct ACPAuthCapabilities: Codable, Sendable, Equatable {
    public var logout: ACPLogoutCapabilities?

    public init(logout: ACPLogoutCapabilities? = nil) {
        self.logout = logout
    }
}

public struct ACPLogoutCapabilities: Codable, Sendable, Equatable {
    public init() {}
}

public struct ACPSessionCapabilities: Codable, Sendable, Equatable {
    public var list: ACPSessionListCapabilities?
    public var resume: ACPSessionResumeCapabilities?
    public var fork: ACPSessionForkCapabilities?
    public var delete: ACPSessionDeleteCapabilities?
    public var export: ACPSessionExportCapabilities?

    public init(
        list: ACPSessionListCapabilities? = nil,
        resume: ACPSessionResumeCapabilities? = nil,
        fork: ACPSessionForkCapabilities? = nil,
        delete: ACPSessionDeleteCapabilities? = nil,
        export: ACPSessionExportCapabilities? = nil
    ) {
        self.list = list
        self.resume = resume
        self.fork = fork
        self.delete = delete
        self.export = export
    }
}

public struct ACPSessionListCapabilities: Codable, Sendable, Equatable {
    public init() {}
}

public struct ACPSessionResumeCapabilities: Codable, Sendable, Equatable {
    public init() {}
}

public struct ACPSessionForkCapabilities: Codable, Sendable, Equatable {
    public init() {}
}

public struct ACPSessionDeleteCapabilities: Codable, Sendable, Equatable {
    public init() {}
}

public struct ACPSessionExportCapabilities: Codable, Sendable, Equatable {
    public init() {}
}

public struct ACPInitializeParams: Codable, Sendable, Equatable {
    public var protocolVersion: Int
    public var clientCapabilities: ACPClientCapabilities
    public var clientInfo: ACPImplementationInfo?

    public init(protocolVersion: Int = 1, clientCapabilities: ACPClientCapabilities = .init(), clientInfo: ACPImplementationInfo? = nil) {
        self.protocolVersion = protocolVersion
        self.clientCapabilities = clientCapabilities
        self.clientInfo = clientInfo
    }
}

public struct ACPInitializeResult: Codable, Sendable, Equatable {
    public var protocolVersion: Int
    public var agentCapabilities: ACPAgentCapabilities
    public var agentInfo: ACPImplementationInfo?
    public var authMethods: [ACPAuthMethod]

    public init(
        protocolVersion: Int = 1,
        agentCapabilities: ACPAgentCapabilities,
        agentInfo: ACPImplementationInfo? = nil,
        authMethods: [ACPAuthMethod] = []
    ) {
        self.protocolVersion = protocolVersion
        self.agentCapabilities = agentCapabilities
        self.agentInfo = agentInfo
        self.authMethods = authMethods
    }

    private enum CodingKeys: String, CodingKey {
        case protocolVersion
        case agentCapabilities
        case agentInfo
        case authMethods
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.protocolVersion = try container.decode(Int.self, forKey: .protocolVersion)
        self.agentCapabilities = try container.decodeIfPresent(ACPAgentCapabilities.self, forKey: .agentCapabilities) ?? .init()
        self.agentInfo = try container.decodeIfPresent(ACPImplementationInfo.self, forKey: .agentInfo)
        self.authMethods = try container.decodeIfPresent([ACPAuthMethod].self, forKey: .authMethods) ?? []
    }
}

public struct ACPAuthMethod: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var description: String?

    public init(id: String, name: String, description: String? = nil) {
        self.id = id
        self.name = name
        self.description = description
    }
}

public struct ACPAuthenticateParams: Codable, Sendable, Equatable {
    public var methodId: String

    public init(methodId: String) {
        self.methodId = methodId
    }
}

public struct ACPAuthenticateResult: Codable, Sendable, Equatable {
    public init() {}
}

public struct ACPLogoutParams: Codable, Sendable, Equatable {
    public init() {}
}

public struct ACPLogoutResult: Codable, Sendable, Equatable {
    public init() {}
}

public struct ACPEnvVar: Codable, Sendable, Equatable {
    public var name: String
    public var value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

public struct ACPHTTPHeader: Codable, Sendable, Equatable {
    public var name: String
    public var value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

public struct ACPMCPServerConfig: Codable, Sendable, Equatable {
    public enum TransportType: String, Codable, Sendable {
        case stdio
        case http
        case sse
    }

    public var type: TransportType
    public var name: String
    public var command: String?
    public var args: [String]
    public var env: [ACPEnvVar]
    public var url: String?
    public var headers: [ACPHTTPHeader]

    public init(
        type: TransportType = .stdio,
        name: String,
        command: String? = nil,
        args: [String] = [],
        env: [ACPEnvVar] = [],
        url: String? = nil,
        headers: [ACPHTTPHeader] = []
    ) {
        self.type = type
        self.name = name
        self.command = command
        self.args = args
        self.env = env
        self.url = url
        self.headers = headers
    }

    public init(name: String, command: String, args: [String] = [], env: [ACPEnvVar] = []) {
        self.init(type: .stdio, name: name, command: command, args: args, env: env)
    }
}

public struct ACPSessionNewParams: Codable, Sendable, Equatable {
    public var cwd: String
    public var mcpServers: [ACPMCPServerConfig]

    public init(cwd: String, mcpServers: [ACPMCPServerConfig] = []) {
        self.cwd = cwd
        self.mcpServers = mcpServers
    }
}

public struct ACPSessionLoadParams: Codable, Sendable, Equatable {
    public var sessionId: String
    public var cwd: String
    public var mcpServers: [ACPMCPServerConfig]

    public init(sessionId: String, cwd: String, mcpServers: [ACPMCPServerConfig] = []) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.mcpServers = mcpServers
    }
}

public struct ACPSessionMode: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var description: String?

    public init(id: String, name: String, description: String? = nil) {
        self.id = id
        self.name = name
        self.description = description
    }
}

public struct ACPSessionModeState: Codable, Sendable, Equatable {
    public var currentModeId: String
    public var availableModes: [ACPSessionMode]

    public init(currentModeId: String, availableModes: [ACPSessionMode]) {
        self.currentModeId = currentModeId
        self.availableModes = availableModes
    }
}

public struct ACPModelInfo: Codable, Sendable, Equatable {
    public var modelId: String
    public var name: String
    public var description: String?

    public init(modelId: String, name: String, description: String? = nil) {
        self.modelId = modelId
        self.name = name
        self.description = description
    }
}

public struct ACPSessionModelState: Codable, Sendable, Equatable {
    public var currentModelId: String
    public var availableModels: [ACPModelInfo]

    public init(currentModelId: String, availableModels: [ACPModelInfo]) {
        self.currentModelId = currentModelId
        self.availableModels = availableModels
    }
}

public enum ACPSessionConfigOptionKind: String, Codable, Sendable {
    case select
    case boolean
}

public enum ACPSessionConfigOptionCategory: String, Codable, Sendable {
    case mode
    case model
    case thoughtLevel = "thought_level"
    case other
}

public struct ACPSessionConfigSelectOption: Codable, Sendable, Equatable {
    public var value: String
    public var name: String
    public var description: String?

    public init(value: String, name: String, description: String? = nil) {
        self.value = value
        self.name = name
        self.description = description
    }
}

public struct ACPSessionConfigSelectGroup: Codable, Sendable, Equatable {
    public var group: String
    public var name: String
    public var options: [ACPSessionConfigSelectOption]

    public init(group: String, name: String, options: [ACPSessionConfigSelectOption]) {
        self.group = group
        self.name = name
        self.options = options
    }
}

public enum ACPSessionConfigSelectOptions: Codable, Sendable, Equatable {
    case ungrouped([ACPSessionConfigSelectOption])
    case grouped([ACPSessionConfigSelectGroup])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let groups = try? container.decode([ACPSessionConfigSelectGroup].self) {
            self = .grouped(groups)
            return
        }
        self = .ungrouped(try container.decode([ACPSessionConfigSelectOption].self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .ungrouped(let options):
            try container.encode(options)
        case .grouped(let groups):
            try container.encode(groups)
        }
    }
}

public struct ACPSessionConfigOption: Codable, Sendable, Equatable {
    public var type: ACPSessionConfigOptionKind
    public var id: String
    public var name: String
    public var description: String?
    public var category: ACPSessionConfigOptionCategory?
    public var currentValue: String
    public var options: ACPSessionConfigSelectOptions

    public init(
        type: ACPSessionConfigOptionKind = .select,
        id: String,
        name: String,
        description: String? = nil,
        category: ACPSessionConfigOptionCategory? = nil,
        currentValue: String,
        options: ACPSessionConfigSelectOptions = .ungrouped([])
    ) {
        self.type = type
        self.id = id
        self.name = name
        self.description = description
        self.category = category
        self.currentValue = currentValue
        self.options = options
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case id
        case name
        case description
        case category
        case currentValue
        case options
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(ACPSessionConfigOptionKind.self, forKey: .type) ?? .select
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        category = try container.decodeIfPresent(ACPSessionConfigOptionCategory.self, forKey: .category)
        if let stringValue = try? container.decode(String.self, forKey: .currentValue) {
            currentValue = stringValue
        } else if let boolValue = try? container.decode(Bool.self, forKey: .currentValue) {
            currentValue = boolValue ? "true" : "false"
        } else if let intValue = try? container.decode(Int.self, forKey: .currentValue) {
            currentValue = String(intValue)
        } else if let doubleValue = try? container.decode(Double.self, forKey: .currentValue) {
            currentValue = String(doubleValue)
        } else {
            throw DecodingError.dataCorruptedError(forKey: .currentValue, in: container, debugDescription: "Unsupported currentValue type")
        }
        options = try container.decodeIfPresent(ACPSessionConfigSelectOptions.self, forKey: .options) ?? .ungrouped([])
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(category, forKey: .category)
        if type == .boolean {
            switch currentValue.lowercased() {
            case "true":
                try container.encode(true, forKey: .currentValue)
            case "false":
                try container.encode(false, forKey: .currentValue)
            default:
                try container.encode(currentValue, forKey: .currentValue)
            }
        } else {
            try container.encode(currentValue, forKey: .currentValue)
        }
        try container.encode(options, forKey: .options)
    }
}

public struct ACPSessionNewResult: Codable, Sendable, Equatable {
    public var sessionId: String
    public var modes: ACPSessionModeState?
    public var models: ACPSessionModelState?
    public var configOptions: [ACPSessionConfigOption]?

    public init(
        sessionId: String,
        modes: ACPSessionModeState? = nil,
        models: ACPSessionModelState? = nil,
        configOptions: [ACPSessionConfigOption]? = nil
    ) {
        self.sessionId = sessionId
        self.modes = modes
        self.models = models
        self.configOptions = configOptions
    }
}

public struct ACPSessionLoadResult: Codable, Sendable, Equatable {
    public var modes: ACPSessionModeState?
    public var models: ACPSessionModelState?
    public var configOptions: [ACPSessionConfigOption]?

    public init(
        modes: ACPSessionModeState? = nil,
        models: ACPSessionModelState? = nil,
        configOptions: [ACPSessionConfigOption]? = nil
    ) {
        self.modes = modes
        self.models = models
        self.configOptions = configOptions
    }
}

public struct ACPTextContentBlock: Codable, Sendable, Equatable {
    public var text: String
    public var annotations: AnyCodable?

    public init(text: String, annotations: AnyCodable? = nil) {
        self.text = text
        self.annotations = annotations
    }
}

public struct ACPImageContentBlock: Codable, Sendable, Equatable {
    public var data: String
    public var mimeType: String
    public var uri: String?
    public var annotations: AnyCodable?

    public init(data: String, mimeType: String, uri: String? = nil, annotations: AnyCodable? = nil) {
        self.data = data
        self.mimeType = mimeType
        self.uri = uri
        self.annotations = annotations
    }
}

public struct ACPAudioContentBlock: Codable, Sendable, Equatable {
    public var data: String
    public var mimeType: String
    public var annotations: AnyCodable?

    public init(data: String, mimeType: String, annotations: AnyCodable? = nil) {
        self.data = data
        self.mimeType = mimeType
        self.annotations = annotations
    }
}

public struct ACPResourceLinkContentBlock: Codable, Sendable, Equatable {
    public var name: String
    public var uri: String
    public var description: String?
    public var mimeType: String?
    public var size: Int64?
    public var title: String?
    public var annotations: AnyCodable?

    public init(
        name: String,
        uri: String,
        description: String? = nil,
        mimeType: String? = nil,
        size: Int64? = nil,
        title: String? = nil,
        annotations: AnyCodable? = nil
    ) {
        self.name = name
        self.uri = uri
        self.description = description
        self.mimeType = mimeType
        self.size = size
        self.title = title
        self.annotations = annotations
    }
}

public struct ACPResourceContentBlock: Codable, Sendable, Equatable {
    public var resource: AnyCodable
    public var annotations: AnyCodable?

    public init(resource: AnyCodable, annotations: AnyCodable? = nil) {
        self.resource = resource
        self.annotations = annotations
    }
}

public struct ACPUnknownContentBlock: Codable, Sendable, Equatable {
    public var type: String
    public var payload: [String: AnyCodable]

    public init(type: String, payload: [String: AnyCodable]) {
        self.type = type
        self.payload = payload
    }
}

public enum ACPContentBlock: Codable, Sendable, Equatable {
    case text(ACPTextContentBlock)
    case image(ACPImageContentBlock)
    case audio(ACPAudioContentBlock)
    case resourceLink(ACPResourceLinkContentBlock)
    case resource(ACPResourceContentBlock)
    case unknown(ACPUnknownContentBlock)

    public init(
        type: String = "text",
        text: String? = nil,
        data: String? = nil,
        mimeType: String? = nil,
        uri: String? = nil,
        name: String? = nil,
        description: String? = nil,
        size: Int64? = nil,
        title: String? = nil,
        resource: AnyCodable? = nil,
        annotations: AnyCodable? = nil
    ) {
        switch type {
        case "text":
            self = .text(.init(text: text ?? "", annotations: annotations))
        case "image":
            self = .image(.init(data: data ?? "", mimeType: mimeType ?? "", uri: uri, annotations: annotations))
        case "audio":
            self = .audio(.init(data: data ?? "", mimeType: mimeType ?? "", annotations: annotations))
        case "resource_link":
            self = .resourceLink(
                .init(
                    name: name ?? "",
                    uri: uri ?? "",
                    description: description,
                    mimeType: mimeType,
                    size: size,
                    title: title,
                    annotations: annotations
                )
            )
        case "resource":
            self = .resource(.init(resource: resource ?? AnyCodable([String: AnyCodable]()), annotations: annotations))
        default:
            var payload: [String: AnyCodable] = [:]
            if let text { payload["text"] = AnyCodable(text) }
            if let data { payload["data"] = AnyCodable(data) }
            if let mimeType { payload["mimeType"] = AnyCodable(mimeType) }
            if let uri { payload["uri"] = AnyCodable(uri) }
            if let name { payload["name"] = AnyCodable(name) }
            if let description { payload["description"] = AnyCodable(description) }
            if let size { payload["size"] = AnyCodable(Double(size)) }
            if let title { payload["title"] = AnyCodable(title) }
            if let resource { payload["resource"] = resource }
            if let annotations { payload["annotations"] = annotations }
            self = .unknown(.init(type: type, payload: payload))
        }
    }

    public static func text(_ value: String) -> ACPContentBlock {
        .text(ACPTextContentBlock(text: value))
    }

    public static func image(data: String, mimeType: String, uri: String? = nil) -> ACPContentBlock {
        .image(.init(data: data, mimeType: mimeType, uri: uri))
    }

    public static func audio(data: String, mimeType: String) -> ACPContentBlock {
        .audio(.init(data: data, mimeType: mimeType))
    }

    public static func resourceLink(
        name: String,
        uri: String,
        description: String? = nil,
        mimeType: String? = nil,
        size: Int64? = nil,
        title: String? = nil
    ) -> ACPContentBlock {
        .resourceLink(
            .init(
                name: name,
                uri: uri,
                description: description,
                mimeType: mimeType,
                size: size,
                title: title
            )
        )
    }

    public var type: String {
        switch self {
        case .text: return "text"
        case .image: return "image"
        case .audio: return "audio"
        case .resourceLink: return "resource_link"
        case .resource: return "resource"
        case .unknown(let block): return block.type
        }
    }

    public var text: String? {
        if case .text(let block) = self { return block.text }
        if case .unknown(let block) = self, let value = Self.stringValue(from: block.payload["text"]) { return value }
        return nil
    }

    public var data: String? {
        switch self {
        case .image(let block): return block.data
        case .audio(let block): return block.data
        case .unknown(let block):
            if let value = Self.stringValue(from: block.payload["data"]) { return value }
            return nil
        default:
            return nil
        }
    }

    public var mimeType: String? {
        switch self {
        case .image(let block): return block.mimeType
        case .audio(let block): return block.mimeType
        case .resourceLink(let block): return block.mimeType
        case .unknown(let block):
            if let value = Self.stringValue(from: block.payload["mimeType"]) { return value }
            return nil
        default:
            return nil
        }
    }

    public var uri: String? {
        switch self {
        case .image(let block): return block.uri
        case .resourceLink(let block): return block.uri
        case .unknown(let block):
            if let value = Self.stringValue(from: block.payload["uri"]) { return value }
            return nil
        default:
            return nil
        }
    }

    public var name: String? {
        switch self {
        case .resourceLink(let block): return block.name
        case .unknown(let block):
            if let value = Self.stringValue(from: block.payload["name"]) { return value }
            return nil
        default:
            return nil
        }
    }

    public var description: String? {
        switch self {
        case .resourceLink(let block): return block.description
        case .unknown(let block):
            if let value = Self.stringValue(from: block.payload["description"]) { return value }
            return nil
        default:
            return nil
        }
    }

    public var size: Int64? {
        switch self {
        case .resourceLink(let block): return block.size
        case .unknown(let block):
            if let value = Self.numberValue(from: block.payload["size"]) { return Int64(value) }
            return nil
        default:
            return nil
        }
    }

    public var title: String? {
        switch self {
        case .resourceLink(let block): return block.title
        case .unknown(let block):
            if let value = Self.stringValue(from: block.payload["title"]) { return value }
            return nil
        default:
            return nil
        }
    }

    public var resource: AnyCodable? {
        switch self {
        case .resource(let block): return block.resource
        case .unknown(let block): return block.payload["resource"]
        default: return nil
        }
    }

    public var annotations: AnyCodable? {
        switch self {
        case .text(let block): return block.annotations
        case .image(let block): return block.annotations
        case .audio(let block): return block.annotations
        case .resourceLink(let block): return block.annotations
        case .resource(let block): return block.annotations
        case .unknown(let block): return block.payload["annotations"]
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(AnyCodable.self)
        guard let object = try? value.decode(to: [String: AnyCodable].self) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Content block must be an object")
        }
        guard let type = Self.decodeString(object, key: "type") else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Missing content block type")
        }
        switch type {
        case "text":
            self = .text(.init(
                text: Self.decodeString(object, key: "text") ?? "",
                annotations: object["annotations"]
            ))
        case "image":
            self = .image(.init(
                data: Self.decodeString(object, key: "data") ?? "",
                mimeType: Self.decodeString(object, key: "mimeType") ?? "",
                uri: Self.decodeString(object, key: "uri"),
                annotations: object["annotations"]
            ))
        case "audio":
            self = .audio(.init(
                data: Self.decodeString(object, key: "data") ?? "",
                mimeType: Self.decodeString(object, key: "mimeType") ?? "",
                annotations: object["annotations"]
            ))
        case "resource_link":
            self = .resourceLink(.init(
                name: Self.decodeString(object, key: "name") ?? "",
                uri: Self.decodeString(object, key: "uri") ?? "",
                description: Self.decodeString(object, key: "description"),
                mimeType: Self.decodeString(object, key: "mimeType"),
                size: Self.decodeInt64(object, key: "size"),
                title: Self.decodeString(object, key: "title"),
                annotations: object["annotations"]
            ))
        case "resource":
            self = .resource(.init(
                resource: object["resource"] ?? AnyCodable([String: AnyCodable]()),
                annotations: object["annotations"]
            ))
        default:
            var payload = object
            payload.removeValue(forKey: "type")
            self = .unknown(.init(type: type, payload: payload))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var object: [String: AnyCodable] = ["type": AnyCodable(type)]
        switch self {
        case .text(let block):
            object["text"] = AnyCodable(block.text)
            if let annotations = block.annotations { object["annotations"] = annotations }
        case .image(let block):
            object["data"] = AnyCodable(block.data)
            object["mimeType"] = AnyCodable(block.mimeType)
            if let uri = block.uri { object["uri"] = AnyCodable(uri) }
            if let annotations = block.annotations { object["annotations"] = annotations }
        case .audio(let block):
            object["data"] = AnyCodable(block.data)
            object["mimeType"] = AnyCodable(block.mimeType)
            if let annotations = block.annotations { object["annotations"] = annotations }
        case .resourceLink(let block):
            object["name"] = AnyCodable(block.name)
            object["uri"] = AnyCodable(block.uri)
            if let description = block.description { object["description"] = AnyCodable(description) }
            if let mimeType = block.mimeType { object["mimeType"] = AnyCodable(mimeType) }
            if let size = block.size { object["size"] = AnyCodable(Double(size)) }
            if let title = block.title { object["title"] = AnyCodable(title) }
            if let annotations = block.annotations { object["annotations"] = annotations }
        case .resource(let block):
            object["resource"] = block.resource
            if let annotations = block.annotations { object["annotations"] = annotations }
        case .unknown(let block):
            for (key, value) in block.payload {
                object[key] = value
            }
        }

        var container = encoder.singleValueContainer()
        try container.encode(AnyCodable(object))
    }

    private static func decodeString(_ object: [String: AnyCodable], key: String) -> String? {
        stringValue(from: object[key])
    }

    private static func decodeInt64(_ object: [String: AnyCodable], key: String) -> Int64? {
        guard let value = numberValue(from: object[key]) else { return nil }
        return Int64(value)
    }

    private static func stringValue(from value: AnyCodable?) -> String? {
        value?.value as? String
    }

    private static func numberValue(from value: AnyCodable?) -> Double? {
        guard let raw = value?.value else { return nil }
        switch raw {
        case let v as Double: return v
        case let v as Float: return Double(v)
        case let v as Int: return Double(v)
        case let v as Int8: return Double(v)
        case let v as Int16: return Double(v)
        case let v as Int32: return Double(v)
        case let v as Int64: return Double(v)
        case let v as UInt: return Double(v)
        case let v as UInt8: return Double(v)
        case let v as UInt16: return Double(v)
        case let v as UInt32: return Double(v)
        case let v as UInt64: return Double(v)
        default: return nil
        }
    }
}

public typealias ACPPromptContent = ACPContentBlock

public struct ACPSessionPromptParams: Codable, Sendable, Equatable {
    public var sessionId: String
    public var prompt: [ACPPromptContent]

    public init(sessionId: String, prompt: [ACPPromptContent]) {
        self.sessionId = sessionId
        self.prompt = prompt
    }
}

public struct ACPSessionPromptResult: Codable, Sendable, Equatable {
    public var stopReason: ACPStopReason

    public init(stopReason: ACPStopReason) {
        self.stopReason = stopReason
    }
}

public struct ACPSessionListParams: Codable, Sendable, Equatable {
    public var cwd: String?
    public var cursor: String?

    public init(cwd: String? = nil, cursor: String? = nil) {
        self.cwd = cwd
        self.cursor = cursor
    }
}

public struct ACPSessionInfo: Codable, Sendable, Equatable {
    public var sessionId: String
    public var cwd: String
    public var title: String?
    public var updatedAt: String?
    public var parentSessionId: String?
    public var messageCount: Int?

    public init(
        sessionId: String,
        cwd: String,
        title: String? = nil,
        updatedAt: String? = nil,
        parentSessionId: String? = nil,
        messageCount: Int? = nil
    ) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.title = title
        self.updatedAt = updatedAt
        self.parentSessionId = parentSessionId
        self.messageCount = messageCount
    }
}

public struct ACPSessionListResult: Codable, Sendable, Equatable {
    public var sessions: [ACPSessionInfo]
    public var nextCursor: String?

    public init(sessions: [ACPSessionInfo], nextCursor: String? = nil) {
        self.sessions = sessions
        self.nextCursor = nextCursor
    }
}

public struct ACPSessionResumeParams: Codable, Sendable, Equatable {
    public var sessionId: String
    public var cwd: String
    public var mcpServers: [ACPMCPServerConfig]

    public init(sessionId: String, cwd: String, mcpServers: [ACPMCPServerConfig] = []) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.mcpServers = mcpServers
    }
}

public struct ACPSessionResumeResult: Codable, Sendable, Equatable {
    public var modes: ACPSessionModeState?
    public var models: ACPSessionModelState?
    public var configOptions: [ACPSessionConfigOption]?

    public init(
        modes: ACPSessionModeState? = nil,
        models: ACPSessionModelState? = nil,
        configOptions: [ACPSessionConfigOption]? = nil
    ) {
        self.modes = modes
        self.models = models
        self.configOptions = configOptions
    }
}

public struct ACPSessionForkParams: Codable, Sendable, Equatable {
    public var sessionId: String
    public var cwd: String
    public var mcpServers: [ACPMCPServerConfig]

    public init(sessionId: String, cwd: String, mcpServers: [ACPMCPServerConfig] = []) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.mcpServers = mcpServers
    }
}

public struct ACPSessionForkResult: Codable, Sendable, Equatable {
    public var sessionId: String
    public var modes: ACPSessionModeState?
    public var models: ACPSessionModelState?
    public var configOptions: [ACPSessionConfigOption]?

    public init(
        sessionId: String,
        modes: ACPSessionModeState? = nil,
        models: ACPSessionModelState? = nil,
        configOptions: [ACPSessionConfigOption]? = nil
    ) {
        self.sessionId = sessionId
        self.modes = modes
        self.models = models
        self.configOptions = configOptions
    }
}

public struct ACPSessionDeleteParams: Codable, Sendable, Equatable {
    public var sessionId: String

    public init(sessionId: String) {
        self.sessionId = sessionId
    }
}

public struct ACPSessionDeleteResult: Codable, Sendable, Equatable {
    public init() {}
}

public enum ACPSessionExportFormat: String, Codable, Sendable, Equatable {
    case jsonl
}

public struct ACPSessionExportParams: Codable, Sendable, Equatable {
    public var sessionId: String
    public var format: ACPSessionExportFormat

    public init(
        sessionId: String,
        format: ACPSessionExportFormat = .jsonl
    ) {
        self.sessionId = sessionId
        self.format = format
    }
}

public struct ACPSessionExportResult: Codable, Sendable, Equatable {
    public var sessionId: String
    public var format: ACPSessionExportFormat
    public var mimeType: String
    public var content: String

    public init(
        sessionId: String,
        format: ACPSessionExportFormat = .jsonl,
        mimeType: String,
        content: String
    ) {
        self.sessionId = sessionId
        self.format = format
        self.mimeType = mimeType
        self.content = content
    }
}

public struct ACPSessionSetModeParams: Codable, Sendable, Equatable {
    public var sessionId: String
    public var modeId: String

    public init(sessionId: String, modeId: String) {
        self.sessionId = sessionId
        self.modeId = modeId
    }
}

public struct ACPSessionSetModeResult: Codable, Sendable, Equatable {
    public init() {}
}

public struct ACPSessionSetModelParams: Codable, Sendable, Equatable {
    public var sessionId: String
    public var modelId: String

    public init(sessionId: String, modelId: String) {
        self.sessionId = sessionId
        self.modelId = modelId
    }
}

public struct ACPSessionSetModelResult: Codable, Sendable, Equatable {
    public init() {}
}

public struct ACPSessionSetConfigOptionParams: Codable, Sendable, Equatable {
    public var sessionId: String
    public var configId: String
    public var value: String

    public init(sessionId: String, configId: String, value: String) {
        self.sessionId = sessionId
        self.configId = configId
        self.value = value
    }
}

public struct ACPSessionSetConfigOptionResult: Codable, Sendable, Equatable {
    public var configOptions: [ACPSessionConfigOption]

    public init(configOptions: [ACPSessionConfigOption]) {
        self.configOptions = configOptions
    }
}

public struct ACPSessionCancelParams: Codable, Sendable, Equatable {
    public var sessionId: String

    public init(sessionId: String) {
        self.sessionId = sessionId
    }
}

public struct ACPSessionStopResult: Codable, Sendable, Equatable {
    public init() {}
}

public struct ACPCancelRequestParams: Codable, Sendable, Equatable {
    public var requestId: JSONRPC.ID

    public init(requestId: JSONRPC.ID) {
        self.requestId = requestId
    }
}

public enum ACPPermissionOptionKind: String, Codable, Sendable {
    case allowOnce = "allow_once"
    case allowAlways = "allow_always"
    case rejectOnce = "reject_once"
    case rejectAlways = "reject_always"
}

public enum ACPToolKind: String, Codable, Sendable {
    case read
    case edit
    case delete
    case move
    case search
    case execute
    case think
    case fetch
    case switchMode = "switch_mode"
    case other
}

public enum ACPToolCallStatus: String, Codable, Sendable {
    case pending
    case inProgress = "in_progress"
    case completed
    case failed
}

public struct ACPToolCallLocation: Codable, Sendable, Equatable {
    public var path: String
    public var line: UInt?

    public init(path: String, line: UInt? = nil) {
        self.path = path
        self.line = line
    }
}

public struct ACPToolCallDiffContent: Codable, Sendable, Equatable {
    public var path: String
    public var newText: String
    public var oldText: String?

    public init(path: String, newText: String, oldText: String? = nil) {
        self.path = path
        self.newText = newText
        self.oldText = oldText
    }
}

public struct ACPToolCallTerminalContent: Codable, Sendable, Equatable {
    public var terminalId: String

    public init(terminalId: String) {
        self.terminalId = terminalId
    }
}

public enum ACPToolCallContent: Codable, Sendable, Equatable {
    case content(AnyCodable)
    case diff(ACPToolCallDiffContent)
    case terminal(ACPToolCallTerminalContent)

    private enum CodingKeys: String, CodingKey {
        case type
        case content
        case path
        case newText
        case oldText
        case terminalId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "content":
            self = .content(try container.decode(AnyCodable.self, forKey: .content))
        case "diff":
            self = .diff(
                .init(
                    path: try container.decode(String.self, forKey: .path),
                    newText: try container.decode(String.self, forKey: .newText),
                    oldText: try container.decodeIfPresent(String.self, forKey: .oldText)
                )
            )
        case "terminal":
            self = .terminal(.init(terminalId: try container.decode(String.self, forKey: .terminalId)))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown tool call content type: \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .content(let value):
            try container.encode("content", forKey: .type)
            try container.encode(value, forKey: .content)
        case .diff(let diff):
            try container.encode("diff", forKey: .type)
            try container.encode(diff.path, forKey: .path)
            try container.encode(diff.newText, forKey: .newText)
            try container.encodeIfPresent(diff.oldText, forKey: .oldText)
        case .terminal(let terminal):
            try container.encode("terminal", forKey: .type)
            try container.encode(terminal.terminalId, forKey: .terminalId)
        }
    }
}

public struct ACPPermissionOption: Codable, Sendable, Equatable {
    public var optionId: String
    public var name: String
    public var kind: ACPPermissionOptionKind

    public init(optionId: String, name: String, kind: ACPPermissionOptionKind) {
        self.optionId = optionId
        self.name = name
        self.kind = kind
    }
}

public struct ACPToolCallUpdate: Codable, Sendable, Equatable {
    public var toolCallId: String
    public var title: String?
    public var kind: ACPToolKind?
    public var status: ACPToolCallStatus?
    public var content: [ACPToolCallContent]?
    public var locations: [ACPToolCallLocation]?
    public var rawInput: AnyCodable?
    public var rawOutput: AnyCodable?

    public init(
        toolCallId: String,
        title: String? = nil,
        kind: ACPToolKind? = nil,
        status: ACPToolCallStatus? = nil,
        content: [ACPToolCallContent]? = nil,
        locations: [ACPToolCallLocation]? = nil,
        rawInput: AnyCodable? = nil,
        rawOutput: AnyCodable? = nil
    ) {
        self.toolCallId = toolCallId
        self.title = title
        self.kind = kind
        self.status = status
        self.content = content
        self.locations = locations
        self.rawInput = rawInput
        self.rawOutput = rawOutput
    }
}

public struct ACPPlanEntry: Codable, Sendable, Equatable {
    public var content: String
    public var status: String
    public var priority: String?

    public init(content: String, status: String, priority: String? = nil) {
        self.content = content
        self.status = status
        self.priority = priority
    }
}

public struct ACPPlan: Codable, Sendable, Equatable {
    public var entries: [ACPPlanEntry]

    public init(entries: [ACPPlanEntry]) {
        self.entries = entries
    }
}

public struct ACPAvailableCommand: Codable, Sendable, Equatable {
    public var name: String
    public var description: String?

    public init(name: String, description: String? = nil) {
        self.name = name
        self.description = description
    }
}

public struct ACPSessionInfoUpdate: Codable, Sendable, Equatable {
    public var title: String?
    public var updatedAt: String?

    public init(title: String? = nil, updatedAt: String? = nil) {
        self.title = title
        self.updatedAt = updatedAt
    }
}

public enum ACPExecutionState: String, Codable, Sendable {
    case queued
    case running
    case waitingTool = "waiting_tool"
    case retrying
    case completed
    case failed
    case cancelled
    case timedOut = "timed_out"
}

public struct ACPExecutionStateUpdate: Codable, Sendable, Equatable {
    public var state: ACPExecutionState
    public var attempt: Int?
    public var message: String?

    public init(
        state: ACPExecutionState,
        attempt: Int? = nil,
        message: String? = nil
    ) {
        self.state = state
        self.attempt = attempt
        self.message = message
    }
}

public struct ACPRetryUpdate: Codable, Sendable, Equatable {
    public var attempt: Int
    public var maxAttempts: Int
    public var reason: String?

    public init(attempt: Int, maxAttempts: Int, reason: String? = nil) {
        self.attempt = attempt
        self.maxAttempts = maxAttempts
        self.reason = reason
    }
}

public struct ACPAuditUpdate: Codable, Sendable, Equatable {
    public var action: String
    public var decision: String
    public var reason: String?

    public init(action: String, decision: String, reason: String? = nil) {
        self.action = action
        self.decision = decision
        self.reason = reason
    }
}

public enum ACPSessionUpdateKind: String, Codable, Sendable {
    case userMessageChunk = "user_message_chunk"
    case agentMessageChunk = "agent_message_chunk"
    case agentThoughtChunk = "agent_thought_chunk"
    case toolCall = "tool_call"
    case toolCallUpdate = "tool_call_update"
    case plan
    case availableCommandsUpdate = "available_commands_update"
    case currentModeUpdate = "current_mode_update"
    case configOptionUpdate = "config_option_update"
    case sessionInfoUpdate = "session_info_update"
    case executionStateUpdate = "execution_state_update"
    case retryUpdate = "retry_update"
    case auditUpdate = "audit_update"
}

public struct ACPSessionPermissionRequestParams: Codable, Sendable, Equatable {
    public var sessionId: String
    public var toolCall: ACPToolCallUpdate
    public var options: [ACPPermissionOption]

    public init(sessionId: String, toolCall: ACPToolCallUpdate, options: [ACPPermissionOption]) {
        self.sessionId = sessionId
        self.toolCall = toolCall
        self.options = options
    }
}

public struct ACPPermissionSelectedOutcome: Codable, Sendable, Equatable {
    public var optionId: String

    public init(optionId: String) {
        self.optionId = optionId
    }
}

public enum ACPRequestPermissionOutcome: Codable, Sendable, Equatable {
    case cancelled
    case selected(ACPPermissionSelectedOutcome)

    private enum CodingKeys: String, CodingKey {
        case outcome
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let outcomeType = try container.decode(String.self, forKey: .outcome)
        switch outcomeType {
        case "cancelled":
            self = .cancelled
        case "selected":
            self = .selected(try ACPPermissionSelectedOutcome(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(forKey: .outcome, in: container, debugDescription: "Unknown permission outcome: \(outcomeType)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .cancelled:
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("cancelled", forKey: .outcome)
        case .selected(let selected):
            try selected.encode(to: encoder)
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("selected", forKey: .outcome)
        }
    }
}

public struct ACPSessionPermissionRequestResult: Codable, Sendable, Equatable {
    public var outcome: ACPRequestPermissionOutcome

    public init(outcome: ACPRequestPermissionOutcome) {
        self.outcome = outcome
    }
}

public typealias ACPSessionUpdateContent = ACPContentBlock

public enum ACPSessionUpdate: Sendable, Equatable {
    case userMessageChunk(ACPSessionUpdateContent)
    case agentMessageChunk(ACPSessionUpdateContent)
    case agentThoughtChunk(ACPSessionUpdateContent)
    case toolCall(ACPToolCallUpdate)
    case toolCallUpdate(ACPToolCallUpdate)
    case plan(ACPPlan)
    case availableCommandsUpdate([ACPAvailableCommand])
    case currentModeUpdate(String)
    case configOptionUpdate([ACPSessionConfigOption])
    case sessionInfoUpdate(ACPSessionInfoUpdate)
    case executionStateUpdate(ACPExecutionStateUpdate)
    case retryUpdate(ACPRetryUpdate)
    case auditUpdate(ACPAuditUpdate)

    public var kind: ACPSessionUpdateKind {
        switch self {
        case .userMessageChunk: return .userMessageChunk
        case .agentMessageChunk: return .agentMessageChunk
        case .agentThoughtChunk: return .agentThoughtChunk
        case .toolCall: return .toolCall
        case .toolCallUpdate: return .toolCallUpdate
        case .plan: return .plan
        case .availableCommandsUpdate: return .availableCommandsUpdate
        case .currentModeUpdate: return .currentModeUpdate
        case .configOptionUpdate: return .configOptionUpdate
        case .sessionInfoUpdate: return .sessionInfoUpdate
        case .executionStateUpdate: return .executionStateUpdate
        case .retryUpdate: return .retryUpdate
        case .auditUpdate: return .auditUpdate
        }
    }

    public var content: ACPSessionUpdateContent? {
        switch self {
        case .userMessageChunk(let content),
             .agentMessageChunk(let content),
             .agentThoughtChunk(let content):
            return content
        default:
            return nil
        }
    }

    public var toolCall: ACPToolCallUpdate? {
        switch self {
        case .toolCall(let toolCall), .toolCallUpdate(let toolCall):
            return toolCall
        default:
            return nil
        }
    }

    public var plan: ACPPlan? {
        if case .plan(let value) = self { return value }
        return nil
    }

    public var availableCommands: [ACPAvailableCommand]? {
        if case .availableCommandsUpdate(let commands) = self { return commands }
        return nil
    }

    public var currentModeId: String? {
        if case .currentModeUpdate(let modeId) = self { return modeId }
        return nil
    }

    public var configOptions: [ACPSessionConfigOption] {
        if case .configOptionUpdate(let options) = self { return options }
        return []
    }

    public var sessionInfoUpdate: ACPSessionInfoUpdate? {
        if case .sessionInfoUpdate(let info) = self { return info }
        return nil
    }

    public var executionStateUpdate: ACPExecutionStateUpdate? {
        if case .executionStateUpdate(let value) = self { return value }
        return nil
    }

    public var retryUpdate: ACPRetryUpdate? {
        if case .retryUpdate(let value) = self { return value }
        return nil
    }

    public var auditUpdate: ACPAuditUpdate? {
        if case .auditUpdate(let value) = self { return value }
        return nil
    }

    public init(
        sessionUpdate: ACPSessionUpdateKind,
        content: ACPSessionUpdateContent? = nil,
        toolCall: ACPToolCallUpdate? = nil,
        plan: ACPPlan? = nil,
        availableCommands: [ACPAvailableCommand]? = nil,
        currentModeId: String? = nil,
        configOptions: [ACPSessionConfigOption] = [],
        sessionInfoUpdate: ACPSessionInfoUpdate? = nil,
        executionStateUpdate: ACPExecutionStateUpdate? = nil,
        retryUpdate: ACPRetryUpdate? = nil,
        auditUpdate: ACPAuditUpdate? = nil
    ) {
        switch sessionUpdate {
        case .userMessageChunk:
            self = .userMessageChunk(content ?? .text(""))
        case .agentMessageChunk:
            self = .agentMessageChunk(content ?? .text(""))
        case .agentThoughtChunk:
            self = .agentThoughtChunk(content ?? .text(""))
        case .toolCall:
            self = .toolCall(toolCall ?? .init(toolCallId: ""))
        case .toolCallUpdate:
            self = .toolCallUpdate(toolCall ?? .init(toolCallId: ""))
        case .plan:
            self = .plan(plan ?? .init(entries: []))
        case .availableCommandsUpdate:
            self = .availableCommandsUpdate(availableCommands ?? [])
        case .currentModeUpdate:
            self = .currentModeUpdate(currentModeId ?? "")
        case .configOptionUpdate:
            self = .configOptionUpdate(configOptions)
        case .sessionInfoUpdate:
            self = .sessionInfoUpdate(sessionInfoUpdate ?? .init())
        case .executionStateUpdate:
            self = .executionStateUpdate(executionStateUpdate ?? .init(state: .running))
        case .retryUpdate:
            self = .retryUpdate(retryUpdate ?? .init(attempt: 1, maxAttempts: 1))
        case .auditUpdate:
            self = .auditUpdate(auditUpdate ?? .init(action: "", decision: ""))
        }
    }
}

public struct ACPSessionUpdatePayload: Codable, Sendable, Equatable {
    public var update: ACPSessionUpdate

    public var sessionUpdate: ACPSessionUpdateKind { update.kind }
    public var content: ACPSessionUpdateContent? { update.content }
    public var toolCall: ACPToolCallUpdate? { update.toolCall }
    public var plan: ACPPlan? { update.plan }
    public var availableCommands: [ACPAvailableCommand]? { update.availableCommands }
    public var currentModeId: String? { update.currentModeId }
    public var configOptions: [ACPSessionConfigOption] { update.configOptions }
    public var sessionInfoUpdate: ACPSessionInfoUpdate? { update.sessionInfoUpdate }
    public var executionStateUpdate: ACPExecutionStateUpdate? { update.executionStateUpdate }
    public var retryUpdate: ACPRetryUpdate? { update.retryUpdate }
    public var auditUpdate: ACPAuditUpdate? { update.auditUpdate }

    public init(
        update: ACPSessionUpdate
    ) {
        self.update = update
    }

    public init(
        sessionUpdate: ACPSessionUpdateKind,
        content: ACPSessionUpdateContent? = nil,
        toolCall: ACPToolCallUpdate? = nil,
        plan: ACPPlan? = nil,
        availableCommands: [ACPAvailableCommand]? = nil,
        currentModeId: String? = nil,
        configOptions: [ACPSessionConfigOption] = [],
        sessionInfoUpdate: ACPSessionInfoUpdate? = nil,
        executionStateUpdate: ACPExecutionStateUpdate? = nil,
        retryUpdate: ACPRetryUpdate? = nil,
        auditUpdate: ACPAuditUpdate? = nil
    ) {
        self.update = ACPSessionUpdate(
            sessionUpdate: sessionUpdate,
            content: content,
            toolCall: toolCall,
            plan: plan,
            availableCommands: availableCommands,
            currentModeId: currentModeId,
            configOptions: configOptions,
            sessionInfoUpdate: sessionInfoUpdate,
            executionStateUpdate: executionStateUpdate,
            retryUpdate: retryUpdate,
            auditUpdate: auditUpdate
        )
    }

    private enum CodingKeys: String, CodingKey {
        case sessionUpdate
        case content
        case toolCall
        case plan
        case availableCommands
        case currentModeId
        case configOptions
        case title
        case updatedAt
        case executionState
        case retry
        case audit
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(ACPSessionUpdateKind.self, forKey: .sessionUpdate)
        switch kind {
        case .userMessageChunk:
            self.update = .userMessageChunk(try container.decode(ACPSessionUpdateContent.self, forKey: .content))
        case .agentMessageChunk:
            self.update = .agentMessageChunk(try container.decode(ACPSessionUpdateContent.self, forKey: .content))
        case .agentThoughtChunk:
            self.update = .agentThoughtChunk(try container.decode(ACPSessionUpdateContent.self, forKey: .content))
        case .toolCall:
            self.update = .toolCall(try container.decode(ACPToolCallUpdate.self, forKey: .toolCall))
        case .toolCallUpdate:
            self.update = .toolCallUpdate(try container.decode(ACPToolCallUpdate.self, forKey: .toolCall))
        case .plan:
            self.update = .plan(try container.decode(ACPPlan.self, forKey: .plan))
        case .availableCommandsUpdate:
            self.update = .availableCommandsUpdate(try container.decode([ACPAvailableCommand].self, forKey: .availableCommands))
        case .currentModeUpdate:
            self.update = .currentModeUpdate(try container.decode(String.self, forKey: .currentModeId))
        case .configOptionUpdate:
            self.update = .configOptionUpdate(try container.decode([ACPSessionConfigOption].self, forKey: .configOptions))
        case .sessionInfoUpdate:
            self.update = .sessionInfoUpdate(.init(
                title: try container.decodeIfPresent(String.self, forKey: .title),
                updatedAt: try container.decodeIfPresent(String.self, forKey: .updatedAt)
            ))
        case .executionStateUpdate:
            self.update = .executionStateUpdate(try container.decode(ACPExecutionStateUpdate.self, forKey: .executionState))
        case .retryUpdate:
            self.update = .retryUpdate(try container.decode(ACPRetryUpdate.self, forKey: .retry))
        case .auditUpdate:
            self.update = .auditUpdate(try container.decode(ACPAuditUpdate.self, forKey: .audit))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(update.kind, forKey: .sessionUpdate)
        switch update {
        case .userMessageChunk(let content),
             .agentMessageChunk(let content),
             .agentThoughtChunk(let content):
            try container.encode(content, forKey: .content)
        case .toolCall(let toolCall), .toolCallUpdate(let toolCall):
            try container.encode(toolCall, forKey: .toolCall)
        case .plan(let plan):
            try container.encode(plan, forKey: .plan)
        case .availableCommandsUpdate(let commands):
            try container.encode(commands, forKey: .availableCommands)
        case .currentModeUpdate(let modeId):
            try container.encode(modeId, forKey: .currentModeId)
        case .configOptionUpdate(let options):
            try container.encode(options, forKey: .configOptions)
        case .sessionInfoUpdate(let info):
            try container.encodeIfPresent(info.title, forKey: .title)
            try container.encodeIfPresent(info.updatedAt, forKey: .updatedAt)
        case .executionStateUpdate(let value):
            try container.encode(value, forKey: .executionState)
        case .retryUpdate(let value):
            try container.encode(value, forKey: .retry)
        case .auditUpdate(let value):
            try container.encode(value, forKey: .audit)
        }
    }
}

public struct ACPSessionUpdateParams: Codable, Sendable, Equatable {
    public var sessionId: String
    public var update: ACPSessionUpdatePayload

    public init(sessionId: String, update: ACPSessionUpdatePayload) {
        self.sessionId = sessionId
        self.update = update
    }
}

public struct ACPReadTextFileParams: Codable, Sendable, Equatable {
    public var sessionId: String
    public var path: String
    public var line: Int?
    public var limit: Int?

    public init(sessionId: String, path: String, line: Int? = nil, limit: Int? = nil) {
        self.sessionId = sessionId
        self.path = path
        self.line = line
        self.limit = limit
    }
}

public struct ACPReadTextFileResult: Codable, Sendable, Equatable {
    public var content: String

    public init(content: String) {
        self.content = content
    }
}

public struct ACPWriteTextFileParams: Codable, Sendable, Equatable {
    public var sessionId: String
    public var path: String
    public var content: String

    public init(sessionId: String, path: String, content: String) {
        self.sessionId = sessionId
        self.path = path
        self.content = content
    }
}

public struct ACPWriteTextFileResult: Codable, Sendable, Equatable {
    public init() {}
}

public struct ACPTerminalCreateParams: Codable, Sendable, Equatable {
    public var sessionId: String
    public var command: String
    public var args: [String]
    public var cwd: String?
    public var env: [ACPEnvVar]
    public var outputByteLimit: Int?

    public init(
        sessionId: String,
        command: String,
        args: [String] = [],
        cwd: String? = nil,
        env: [ACPEnvVar] = [],
        outputByteLimit: Int? = nil
    ) {
        self.sessionId = sessionId
        self.command = command
        self.args = args
        self.cwd = cwd
        self.env = env
        self.outputByteLimit = outputByteLimit
    }
}

public struct ACPTerminalCreateResult: Codable, Sendable, Equatable {
    public var terminalId: String

    public init(terminalId: String) {
        self.terminalId = terminalId
    }
}

public struct ACPTerminalRefParams: Codable, Sendable, Equatable {
    public var sessionId: String
    public var terminalId: String

    public init(sessionId: String, terminalId: String) {
        self.sessionId = sessionId
        self.terminalId = terminalId
    }
}

public struct ACPTerminalExitStatus: Codable, Sendable, Equatable {
    public var exitCode: Int?
    public var signal: String?

    public init(exitCode: Int? = nil, signal: String? = nil) {
        self.exitCode = exitCode
        self.signal = signal
    }
}

public struct ACPTerminalOutputResult: Codable, Sendable, Equatable {
    public var output: String
    public var truncated: Bool
    public var exitStatus: ACPTerminalExitStatus?

    public init(output: String, truncated: Bool, exitStatus: ACPTerminalExitStatus? = nil) {
        self.output = output
        self.truncated = truncated
        self.exitStatus = exitStatus
    }
}

public struct ACPTerminalWaitForExitResult: Codable, Sendable, Equatable {
    public var exitCode: Int?
    public var signal: String?

    public init(exitCode: Int? = nil, signal: String? = nil) {
        self.exitCode = exitCode
        self.signal = signal
    }
}

public struct ACPTerminalKillResult: Codable, Sendable, Equatable {
    public init() {}
}

public struct ACPTerminalReleaseResult: Codable, Sendable, Equatable {
    public init() {}
}

public enum ACPCodec {
    public static func encodeParams<T: Encodable>(_ value: T) throws -> AnyCodable {
        try JSONRPCCodec.toValue(value)
    }

    public static func decodeParams<T: Decodable>(_ value: JSONRPC.Params?, as type: T.Type = T.self) throws -> T {
        guard let value else {
            throw NSError(domain: "ACPCodec", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing params"])
        }
        let any: AnyCodable
        switch value {
        case .object(let object):
            any = AnyCodable(object)
        case .array(let array):
            any = AnyCodable(array)
        }
        return try JSONRPCCodec.fromValue(any, as: type)
    }

    public static func decodeParams<T: Decodable>(_ value: AnyCodable?, as type: T.Type = T.self) throws -> T {
        guard let value else {
            throw NSError(domain: "ACPCodec", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing params"])
        }
        return try JSONRPCCodec.fromValue(value, as: type)
    }

    public static func decodeResult<T: Decodable>(_ value: AnyCodable?, as type: T.Type = T.self) throws -> T {
        guard let value else {
            throw NSError(domain: "ACPCodec", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing result"])
        }
        return try JSONRPCCodec.fromValue(value, as: type)
    }
}
