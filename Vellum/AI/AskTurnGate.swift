import Foundation

actor AskTurnGate {
    private var busy = false
    private var waiters: [
        (id: UUID, continuation: CheckedContinuation<Void, Error>)
    ] = []
    // Distinguishes cancellation-before-append from cancellation after handoff.
    private var activeWaiterIDs = Set<UUID>()
    private var pendingCancelledIDs = Set<UUID>()

    func acquire() async throws {
        guard busy else {
            try Task.checkCancellation()
            busy = true
            return
        }

        let waiterID = UUID()
        activeWaiterIDs.insert(waiterID)

        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation {
                    (continuation: CheckedContinuation<Void, Error>) in
                    if pendingCancelledIDs.remove(waiterID) != nil
                        || Task.isCancelled {
                        activeWaiterIDs.remove(waiterID)
                        continuation.resume(throwing: CancellationError())
                    } else {
                        waiters.append((id: waiterID, continuation: continuation))
                    }
                }
            } onCancel: {
                Task { await self.cancelWaiter(id: waiterID) }
            }
        } catch {
            activeWaiterIDs.remove(waiterID)
            pendingCancelledIDs.remove(waiterID)
            throw error
        }

        guard !Task.isCancelled else {
            release()
            throw CancellationError()
        }
    }

    func release() {
        guard !waiters.isEmpty else {
            busy = false
            return
        }

        let waiter = waiters.removeFirst()
        activeWaiterIDs.remove(waiter.id)
        waiter.continuation.resume()
    }

    private func cancelWaiter(id: UUID) {
        if let index = waiters.firstIndex(where: { $0.id == id }) {
            let waiter = waiters.remove(at: index)
            activeWaiterIDs.remove(id)
            waiter.continuation.resume(throwing: CancellationError())
        } else if activeWaiterIDs.contains(id) {
            pendingCancelledIDs.insert(id)
        }
    }
}
