import XCTest
import Foundation
@testable import InteropKit

private struct GreetingService: Sendable {
    var greet: @Sendable (String) -> String
}

private enum GreetingDependencyKey: DependencyKey {
    static var liveValue: GreetingService {
        GreetingService { "Hello, \($0)!" }
    }
    static var testValue: GreetingService {
        GreetingService { "Test Hello, \($0)!" }
    }
}

private struct CounterService: Sendable {
    var value: Int
}

private enum CounterDependencyKey: DependencyKey {
    static var liveValue: CounterService { CounterService(value: 100) }
}

extension DependencyValues {
    fileprivate var greeting: GreetingService {
        get { self[GreetingDependencyKey.self] }
        set { self[GreetingDependencyKey.self] = newValue }
    }

    fileprivate var counter: CounterService {
        get { self[CounterDependencyKey.self] }
        set { self[CounterDependencyKey.self] = newValue }
    }
}

final class DependencyContextTests: XCTestCase {

    func testDependencyKeyDefaults() {
        // CounterDependencyKey doesn't specify testValue, so it defaults to liveValue
        XCTAssertEqual(CounterDependencyKey.testValue.value, 100)
        XCTAssertEqual(GreetingDependencyKey.liveValue.greet("World"), "Hello, World!")
        XCTAssertEqual(GreetingDependencyKey.testValue.greet("World"), "Test Hello, World!")
    }

    func testDefaultTestContextResolution() {
        // When running inside XCTest, isTestContext is true by default
        let values = DependencyValues()
        XCTAssertTrue(values.isTestContext)
        XCTAssertEqual(values[GreetingDependencyKey.self].greet("World"), "Test Hello, World!")
        XCTAssertEqual(values[CounterDependencyKey.self].value, 100)

        // If explicitly set to live (isTestContext = false)
        let liveValues = DependencyValues(isTestContext: false)
        XCTAssertFalse(liveValues.isTestContext)
        XCTAssertEqual(liveValues[GreetingDependencyKey.self].greet("World"), "Hello, World!")
    }

    func testSynchronousWithDependenciesScope() throws {
        let initialGreeting = DependencyValues.current[GreetingDependencyKey.self].greet("A")

        withDependencies { values in
            values[GreetingDependencyKey.self] = GreetingService { "Custom: \($0)" }
        } operation: {
            let scopedGreeting = DependencyValues.current[GreetingDependencyKey.self].greet("A")
            XCTAssertEqual(scopedGreeting, "Custom: A")

            // Nested scope
            withDependencies { nested in
                nested[GreetingDependencyKey.self] = GreetingService { "Nested: \($0)" }
            } operation: {
                XCTAssertEqual(DependencyValues.current[GreetingDependencyKey.self].greet("A"), "Nested: A")
            }

            // Restored to parent scope
            XCTAssertEqual(DependencyValues.current[GreetingDependencyKey.self].greet("A"), "Custom: A")
        }

        // Restored to outer scope
        XCTAssertEqual(DependencyValues.current[GreetingDependencyKey.self].greet("A"), initialGreeting)
    }

    func testSynchronousWithDependenciesRethrowsError() {
        enum DummyError: Error { case boom }

        XCTAssertThrowsError(try withDependencies { values in
            values[CounterDependencyKey.self] = CounterService(value: 999)
        } operation: {
            XCTAssertEqual(DependencyValues.current[CounterDependencyKey.self].value, 999)
            throw DummyError.boom
        }) { error in
            XCTAssertEqual(error as? DummyError, .boom)
        }

        // Must still be restored after throwing
        XCTAssertEqual(DependencyValues.current[CounterDependencyKey.self].value, 100)
    }

    func testAsynchronousWithDependenciesScope() async {
        let initialGreeting = DependencyValues.current[GreetingDependencyKey.self].greet("Async")

        await withDependencies { values in
            values.greeting = GreetingService { "AsyncCustom: \($0)" }
        } operation: {
            let scoped = DependencyValues.current.greeting.greet("Async")
            XCTAssertEqual(scoped, "AsyncCustom: Async")

            // Test propagation into child Task
            let childResult = await Task {
                DependencyValues.current.greeting.greet("Child")
            }.value
            XCTAssertEqual(childResult, "AsyncCustom: Child")
        }

        XCTAssertEqual(DependencyValues.current[GreetingDependencyKey.self].greet("Async"), initialGreeting)
    }

    func testConcurrentIsolationBetweenTasks() async {
        // Run 50 concurrent tasks, each with their own unique dependency value
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask {
                    await withDependencies { values in
                        values[CounterDependencyKey.self] = CounterService(value: i)
                    } operation: {
                        // Simulate async interleaving
                        try? await Task.sleep(nanoseconds: UInt64.random(in: 1_000_000...5_000_000))
                        let readValue = DependencyValues.current[CounterDependencyKey.self].value
                        XCTAssertEqual(readValue, i, "Concurrent tasks must not leak or overwrite DependencyValues")
                    }
                }
            }
        }
    }

    func testPropertyWrapperDependency() {
        struct Consumer {
            @Dependency(GreetingDependencyKey.self) var greeting
            @Dependency(\.counter) var counter

            func run() -> (String, Int) {
                (greeting.greet("Consumer"), counter.value)
            }
        }

        let consumer = Consumer()
        let (defaultGreet, defaultCount) = consumer.run()
        XCTAssertEqual(defaultGreet, "Test Hello, Consumer!")
        XCTAssertEqual(defaultCount, 100)

        withDependencies { values in
            values.greeting = GreetingService { "Overridden: \($0)" }
            values.counter = CounterService(value: 42)
        } operation: {
            let (scopedGreet, scopedCount) = consumer.run()
            XCTAssertEqual(scopedGreet, "Overridden: Consumer")
            XCTAssertEqual(scopedCount, 42)
        }

        // Restored
        let (afterGreet, afterCount) = consumer.run()
        XCTAssertEqual(afterGreet, defaultGreet)
        XCTAssertEqual(afterCount, defaultCount)
    }
}
