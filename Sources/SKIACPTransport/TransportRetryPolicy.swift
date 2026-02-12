import Foundation

public struct ACPTransportRetryPolicy: Sendable, Equatable {
    public var maxAttempts: Int
    public var baseDelayNanoseconds: UInt64
    public var maxDelayNanoseconds: UInt64

    public init(
        maxAttempts: Int = 0,
        baseDelayNanoseconds: UInt64 = 200_000_000,
        maxDelayNanoseconds: UInt64 = 3_000_000_000
    ) {
        self.maxAttempts = max(0, maxAttempts)
        self.baseDelayNanoseconds = max(1, baseDelayNanoseconds)
        self.maxDelayNanoseconds = max(self.baseDelayNanoseconds, maxDelayNanoseconds)
    }

    public func canRetry(_ attempt: Int) -> Bool {
        attempt < maxAttempts
    }

    public func delayNanoseconds(for attempt: Int) -> UInt64 {
        guard attempt > 0 else { return 0 }
        let exp = min(attempt - 1, 20)
        let factor = UInt64(1 << exp)
        let candidate = baseDelayNanoseconds.multipliedReportingOverflow(by: factor)
        if candidate.overflow {
            return maxDelayNanoseconds
        }
        return min(candidate.partialValue, maxDelayNanoseconds)
    }
}
