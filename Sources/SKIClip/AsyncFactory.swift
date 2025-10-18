//
// For licensing see accompanying LICENSE file.
// Copyright (C) 2024 Apple Inc. All Rights Reserved.
//

import Foundation

/// Asynchronous factory for slow-to-load types.
public actor AsyncFactory<T: Sendable>: Sendable {

    private enum State {
        case idle( @Sendable () async -> T)
        case initializing(Task<T, Never>)
        case initialized(T)
    }

    private var state: State

    public init(factory: @Sendable @escaping () async -> T) {
        self.state = .idle(factory)
    }

    public func get() async -> T {
        switch state {
        case .idle(let factory):
            let task = Task {
               await factory()
            }
            self.state = .initializing(task)
            let value = await task.value
            self.state = .initialized(value)
            return value

        case .initializing(let task):
            return await task.value

        case .initialized(let v):
            return v
        }
    }
}
