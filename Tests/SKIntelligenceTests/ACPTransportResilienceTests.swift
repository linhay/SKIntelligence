import XCTest
 import STJSON
@testable import SKIACPTransport

final class ACPTransportResilienceTests: XCTestCase {
    func testRetryPolicyBackoffAndCap() {
        let policy = ACPTransportRetryPolicy(
            maxAttempts: 3,
            baseDelayNanoseconds: 100_000_000,
            maxDelayNanoseconds: 250_000_000
        )

        XCTAssertTrue(policy.canRetry(0))
        XCTAssertTrue(policy.canRetry(1))
        XCTAssertTrue(policy.canRetry(2))
        XCTAssertFalse(policy.canRetry(3))

        XCTAssertEqual(policy.delayNanoseconds(for: 1), 100_000_000)
        XCTAssertEqual(policy.delayNanoseconds(for: 2), 200_000_000)
        XCTAssertEqual(policy.delayNanoseconds(for: 3), 250_000_000)
        XCTAssertEqual(policy.delayNanoseconds(for: 10), 250_000_000)
    }

    func testBackpressureGateBlocksUntilRelease() async throws {
        let gate = ACPTransportBackpressureGate(maxInFlight: 1)
        let box = FlagBox()
        await gate.acquire()

        let started = expectation(description: "started waiting")
        let acquired = expectation(description: "acquired after release")

        let waiter = Task {
            started.fulfill()
            await gate.acquire()
            await box.mark()
            acquired.fulfill()
            await gate.release()
        }

        await fulfillment(of: [started], timeout: 1.0)
        try await Task.sleep(nanoseconds: 80_000_000)
        let acquiredBeforeRelease = await box.value
        XCTAssertFalse(acquiredBeforeRelease)

        await gate.release()
        await fulfillment(of: [acquired], timeout: 1.0)
        _ = await waiter.result
    }

    func testBackpressureGateCancelledWaiterDoesNotLeakPermit() async throws {
        let gate = ACPTransportBackpressureGate(maxInFlight: 1)
        await gate.acquire()

        let waiterStarted = expectation(description: "waiter started")
        let waiter = Task {
            waiterStarted.fulfill()
            await gate.acquire()
        }
        await fulfillment(of: [waiterStarted], timeout: 1.0)
        try await Task.sleep(nanoseconds: 80_000_000)

        waiter.cancel()
        await gate.release()

        let followupAcquired = expectation(description: "followup acquired")
        let followup = Task {
            await gate.acquire()
            followupAcquired.fulfill()
            await gate.release()
        }

        await fulfillment(of: [followupAcquired], timeout: 1.0)
        _ = await waiter.result
        _ = await followup.result
    }
}

private actor FlagBox {
    private(set) var value: Bool = false
    func mark() { value = true }
}
