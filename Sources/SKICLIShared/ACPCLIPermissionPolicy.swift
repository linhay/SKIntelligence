import Foundation

public enum SKICLIPermissionPolicyMode: String, Sendable, CaseIterable {
    case ask
    case allow
    case deny
}

public enum SKICLIServePermissionMode: String, Sendable, CaseIterable {
    case disabled
    case permissive
    case required

    public var enabled: Bool {
        self != .disabled
    }

    public var allowOnBridgeError: Bool {
        self == .permissive
    }

    public var policyMode: SKICLIPermissionPolicyMode {
        switch self {
        case .disabled:
            return .allow
        case .permissive, .required:
            return .ask
        }
    }
}

public enum SKICLIClientPermissionDecision: String, Sendable, CaseIterable {
    case allow
    case deny

    public var allowValue: Bool {
        self == .allow
    }
}
