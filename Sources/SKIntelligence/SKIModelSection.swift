//
//  File.swift
//  SKIntelligence
//
//  Created by linhey on 6/12/25.
//

import Foundation

public protocol SKIChatSection {
    func respond(to prompt: SKIPrompt) async throws -> sending String
}
