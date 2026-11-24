import NIOConcurrencyHelpers

extension Task where Failure == any Error {
    /// The task's value, or `CancellationError` as soon as the waiting task is canceled. The task
    /// itself keeps running for its other waiters; a canceled waiter leaves a small task behind until
    /// it ends.
    var valueUnlessCancelled: Success {
        get async throws {
            let waiter = Waiter<Success>()
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    waiter.wait(continuation)
                    Task<Void, Never> { waiter.finish(with: await result) }
                }
            } onCancel: {
                waiter.finish(with: .failure(Swift.CancellationError()))
            }
        }
    }
}

/// Hands one waiting continuation the first of a task's result and the waiter's cancellation.
private final class Waiter<Success: Sendable>: Sendable {
    private enum State {
        case idle
        case waiting(CheckedContinuation<Success, any Error>)
        /// Finished before the continuation arrived: it resumes with this as soon as it does.
        case finished(Result<Success, any Error>)
        case resumed
    }

    private let state = NIOLockedValueBox(State.idle)

    func wait(_ continuation: CheckedContinuation<Success, any Error>) {
        let early: Result<Success, any Error>? = state.withLockedValue { state in
            if case .finished(let result) = state {
                state = .resumed
                return result
            }
            state = .waiting(continuation)
            return nil
        }
        if let early { continuation.resume(with: early) }
    }

    func finish(with result: Result<Success, any Error>) {
        let waiting: CheckedContinuation<Success, any Error>? = state.withLockedValue { state in
            switch state {
            case .idle:
                state = .finished(result)
                return nil
            case .waiting(let continuation):
                state = .resumed
                return continuation
            case .finished, .resumed:
                return nil
            }
        }
        waiting?.resume(with: result)
    }
}
