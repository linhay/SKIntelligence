//
//  File.swift
//  SKIntelligence
//
//  Created by linhey on 6/12/25.
//

import Foundation

/// Protocol for chat session implementations.
public protocol SKIChatSection: Actor {
    /// Responds to a prompt and returns the model's response.
    nonisolated func respond(to prompt: SKIPrompt) async throws -> sending String
}
