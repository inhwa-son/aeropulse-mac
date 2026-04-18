import Foundation

final class ContinuationGate<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, any Error>?

    init(_ continuation: CheckedContinuation<T, any Error>) {
        self.continuation = continuation
    }

    /// Returns true if the continuation was already resumed before this call arrived.
    /// Used by timeout handlers to avoid discarding a healthy XPC connection when
    /// the reply already arrived on time.
    var hasResumed: Bool {
        lock.lock(); defer { lock.unlock() }
        return continuation == nil
    }

    /// Resumes only if not yet resumed. Returns true if this call actually resumed.
    @discardableResult
    func tryResume(returning value: T) -> Bool {
        lock.lock()
        let c = continuation
        continuation = nil
        lock.unlock()
        c?.resume(returning: value)
        return c != nil
    }

    @discardableResult
    func tryResume(throwing error: any Error) -> Bool {
        lock.lock()
        let c = continuation
        continuation = nil
        lock.unlock()
        c?.resume(throwing: error)
        return c != nil
    }

    func resume(returning value: T) {
        _ = tryResume(returning: value)
    }

    func resume(throwing error: any Error) {
        _ = tryResume(throwing: error)
    }
}
