import Foundation
import Testing
@testable import ThrottledParallelKit

import os

private final class SafeCounter: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: 0)

    func add(_ delta: Int) {
        state.withLock { $0 += delta }
    }

    var total: Int {
        state.withLock { $0 }
    }
}

@Suite("ThrottledParallel Tests")
struct ThrottledParallelTests {

    @Test("ThrottledParallel.map preserves order and transforms correctly")
    func testMapOrder() {
        let input = Array(1...100)
        let output = ThrottledParallel.map(input, maxConcurrency: 4) { $0 * 2 }
        #expect(output == input.map { $0 * 2 })
    }

    @Test("ThrottledParallel.forEach iterates over all items")
    func testForEach() {
        let input = Array(1...50)
        let counter = SafeCounter()
        ThrottledParallel.forEach(input, maxConcurrency: 4) { val in
            counter.add(val)
        }
        #expect(counter.total == input.reduce(0, +))
    }
}
