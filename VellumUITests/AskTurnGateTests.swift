import Foundation
@testable import Vellum
import XCTest

private struct AskTurnGateTestTimeoutError: Error {}

private enum AskTurnGateAcquisitionOutcome: Equatable, Sendable {
    case acquired
    case cancelled
    case unexpectedError
}

private actor AskTurnGateTestState {
    private var started = false
    private var acquired = false

    func markStarted() {
        started = true
    }

    func markAcquired() {
        acquired = true
    }

    func hasStarted() -> Bool {
        started
    }

    func hasAcquired() -> Bool {
        acquired
    }
}

private func withAskTurnGateTestTimeout<Value: Sendable>(
    _ duration: Duration = .seconds(1),
    operation: @escaping @Sendable () async throws -> Value
) async throws -> Value {
    try await withThrowingTaskGroup(of: Value.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(for: duration)
            throw AskTurnGateTestTimeoutError()
        }

        defer { group.cancelAll() }
        guard let value = try await group.next() else {
            throw AskTurnGateTestTimeoutError()
        }
        return value
    }
}

private func waitForAskTurnGateState(
    _ predicate: @escaping @Sendable () async -> Bool
) async -> Bool {
    for iteration in 0..<200 {
        if await predicate() {
            return true
        }
        await Task.yield()
        if iteration.isMultiple(of: 20) {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }
    return false
}

@MainActor
final class AskTurnGateTests: XCTestCase {
    func testAcquireReleaseAllowsAnotherAcquire() async throws {
        let gate = AskTurnGate()

        try await withAskTurnGateTestTimeout {
            try await gate.acquire()
        }
        await gate.release()
        try await withAskTurnGateTestTimeout {
            try await gate.acquire()
        }
        await gate.release()
    }

    func testSecondAcquireSuspendsUntilRelease() async throws {
        let gate = AskTurnGate()
        let state = AskTurnGateTestState()
        try await withAskTurnGateTestTimeout {
            try await gate.acquire()
        }

        let secondAcquire = Task {
            await state.markStarted()
            do {
                try await gate.acquire()
                await state.markAcquired()
                await gate.release()
                return AskTurnGateAcquisitionOutcome.acquired
            } catch is CancellationError {
                return AskTurnGateAcquisitionOutcome.cancelled
            } catch {
                return AskTurnGateAcquisitionOutcome.unexpectedError
            }
        }

        let started = await waitForAskTurnGateState {
            await state.hasStarted()
        }
        XCTAssertTrue(started)
        for _ in 0..<20 {
            await Task.yield()
        }
        let acquiredBeforeRelease = await state.hasAcquired()
        XCTAssertFalse(acquiredBeforeRelease)

        await gate.release()
        let outcome = try await withAskTurnGateTestTimeout {
            await secondAcquire.value
        }
        XCTAssertEqual(outcome, .acquired)
        let acquiredAfterRelease = await state.hasAcquired()
        XCTAssertTrue(acquiredAfterRelease)
    }

    func testCancelWhileWaitingRemovesWaiter() async throws {
        let gate = AskTurnGate()
        let state = AskTurnGateTestState()
        try await withAskTurnGateTestTimeout {
            try await gate.acquire()
        }

        let cancelledAcquire = Task {
            await state.markStarted()
            do {
                try await gate.acquire()
                await gate.release()
                return AskTurnGateAcquisitionOutcome.acquired
            } catch is CancellationError {
                return AskTurnGateAcquisitionOutcome.cancelled
            } catch {
                return AskTurnGateAcquisitionOutcome.unexpectedError
            }
        }

        let started = await waitForAskTurnGateState {
            await state.hasStarted()
        }
        XCTAssertTrue(started)
        for _ in 0..<20 {
            await Task.yield()
        }
        cancelledAcquire.cancel()

        let outcome = try await withAskTurnGateTestTimeout {
            await cancelledAcquire.value
        }
        XCTAssertEqual(outcome, .cancelled)

        await gate.release()
        try await withAskTurnGateTestTimeout {
            try await gate.acquire()
        }
        await gate.release()
    }

    func testCancelBeforeAppendAlwaysThrowsPromptly() async throws {
        for _ in 0..<300 {
            let gate = AskTurnGate()
            try await withAskTurnGateTestTimeout {
                try await gate.acquire()
            }

            let cancelledAcquire = Task {
                do {
                    try await gate.acquire()
                    await gate.release()
                    return AskTurnGateAcquisitionOutcome.acquired
                } catch is CancellationError {
                    return AskTurnGateAcquisitionOutcome.cancelled
                } catch {
                    return AskTurnGateAcquisitionOutcome.unexpectedError
                }
            }
            cancelledAcquire.cancel()

            let outcome = try await withAskTurnGateTestTimeout(.milliseconds(250)) {
                await cancelledAcquire.value
            }
            XCTAssertEqual(outcome, .cancelled)
            await gate.release()
        }
    }

    func testConcurrentAcquireCancellationStormLeavesGateUnlocked() async throws {
        let gate = AskTurnGate()
        let taskCount = 100
        let outcomes = try await withAskTurnGateTestTimeout(.seconds(3)) {
            await withTaskGroup(
                of: AskTurnGateAcquisitionOutcome.self,
                returning: [AskTurnGateAcquisitionOutcome].self
            ) { group in
                for taskIndex in 0..<taskCount {
                    group.addTask {
                        // Deterministic pseudo-random cancellation rounds keep this reproducible.
                        let cancellationRound = (taskIndex * 37 + 11) % 5
                        for round in 0..<3 {
                            if round == cancellationRound {
                                withUnsafeCurrentTask { task in
                                    task?.cancel()
                                }
                            }

                            do {
                                try await gate.acquire()
                            } catch is CancellationError {
                                return .cancelled
                            } catch {
                                return .unexpectedError
                            }

                            await Task.yield()
                            await gate.release()
                            await Task.yield()
                        }
                        return .acquired
                    }
                }

                var outcomes: [AskTurnGateAcquisitionOutcome] = []
                for await outcome in group {
                    outcomes.append(outcome)
                }
                return outcomes
            }
        }

        XCTAssertEqual(outcomes.count, taskCount)
        XCTAssertFalse(outcomes.contains(.unexpectedError))
        XCTAssertTrue(outcomes.contains(.cancelled))
        XCTAssertTrue(outcomes.contains(.acquired))

        try await withAskTurnGateTestTimeout {
            try await gate.acquire()
        }
        await gate.release()
    }
}
