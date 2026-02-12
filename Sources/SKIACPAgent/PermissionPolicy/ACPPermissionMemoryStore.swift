import Foundation
import SKIACP

public actor ACPPermissionMemoryStore {
    private var storage: [String: [ACPToolCallFingerprint: ACPRequestPermissionOutcome]] = [:]

    public init() {}

    public func get(sessionId: String, fingerprint: ACPToolCallFingerprint) -> ACPRequestPermissionOutcome? {
        storage[sessionId]?[fingerprint]
    }

    public func set(sessionId: String, fingerprint: ACPToolCallFingerprint, outcome: ACPRequestPermissionOutcome) {
        var byFingerprint = storage[sessionId] ?? [:]
        byFingerprint[fingerprint] = outcome
        storage[sessionId] = byFingerprint
    }

    public func clear(sessionId: String) {
        storage[sessionId] = nil
    }
}
