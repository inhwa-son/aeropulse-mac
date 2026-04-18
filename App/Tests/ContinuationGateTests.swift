import Foundation
import Testing
@testable import AeroPulse

struct ContinuationGateTests {
    @Test
    func tryResumeReturningValueSucceedsOnFirstCallOnly() async throws {
        let value: Int = try await withCheckedThrowingContinuation { continuation in
            let gate = ContinuationGate<Int>(continuation)
            #expect(gate.hasResumed == false)
            #expect(gate.tryResume(returning: 42) == true)
            #expect(gate.hasResumed == true)
            // Subsequent attempts must no-op rather than crash.
            #expect(gate.tryResume(returning: 7) == false)
            #expect(gate.tryResume(throwing: CancellationError()) == false)
        }
        #expect(value == 42)
    }

    @Test
    func tryResumeThrowingPropagatesFirstErrorOnly() async {
        struct BoxedError: Error, Equatable { let tag: String }

        await #expect(throws: BoxedError.self) {
            _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, any Error>) in
                let gate = ContinuationGate<Int>(continuation)
                #expect(gate.tryResume(throwing: BoxedError(tag: "first")) == true)
                #expect(gate.tryResume(throwing: BoxedError(tag: "second")) == false)
                #expect(gate.tryResume(returning: 99) == false)
            }
        }
    }

    @Test
    func concurrentTryResumeLetsExactlyOneCallerWin() async throws {
        actor WinnerCounter {
            var count = 0
            func increment() { count += 1 }
        }
        let counter = WinnerCounter()

        let winningValue: Int = try await withCheckedThrowingContinuation { continuation in
            let gate = ContinuationGate<Int>(continuation)
            let group = DispatchGroup()
            let queue = DispatchQueue(label: "aeropulse.tests.contgate-race", attributes: .concurrent)
            for attempt in 0..<128 {
                group.enter()
                queue.async {
                    if gate.tryResume(returning: attempt) {
                        Task { await counter.increment() }
                    }
                    group.leave()
                }
            }
            group.wait()
        }

        // Exactly one racer wins the resume.
        // We give the winner increment a moment to flush through the actor.
        try? await Task.sleep(for: .milliseconds(50))
        let winners = await counter.count
        #expect(winners == 1)
        _ = winningValue
    }
}
