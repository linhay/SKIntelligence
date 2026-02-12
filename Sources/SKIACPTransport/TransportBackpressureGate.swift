import Foundation

public actor ACPTransportBackpressureGate {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }

    private let maxInFlight: Int
    private var availablePermits: Int
    private var waiters: [Waiter] = []

    public init(maxInFlight: Int) {
        self.maxInFlight = max(1, maxInFlight)
        self.availablePermits = max(1, maxInFlight)
    }

    public func acquire() async {
        if availablePermits > 0 {
            availablePermits -= 1
            return
        }

        let waiterID = UUID()
        let didAcquirePermit = await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                waiters.append(.init(id: waiterID, continuation: continuation))
            }
        }, onCancel: {
            Task { await self.cancelWaiter(id: waiterID) }
        })
        guard didAcquirePermit else { return }
        if Task.isCancelled {
            release()
        }
    }

    public func release() {
        if !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            waiter.continuation.resume(returning: true)
            return
        }
        availablePermits = min(maxInFlight, availablePermits + 1)
    }
}

private extension ACPTransportBackpressureGate {
    func cancelWaiter(id: UUID) {
        if let index = waiters.firstIndex(where: { $0.id == id }) {
            let waiter = waiters.remove(at: index)
            waiter.continuation.resume(returning: false)
        }
    }
}
