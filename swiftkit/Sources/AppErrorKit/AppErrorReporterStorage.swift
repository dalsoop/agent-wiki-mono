import Foundation
import os

// MARK: - Internal Storage State

struct StorageState: Sendable {
    var handlers: [UUID: ErrorHandler] = [:]
    var singleHandler: ErrorHandler? = nil
    var configuration: AppErrorReporter.Configuration

    init(configuration: AppErrorReporter.Configuration) {
        self.configuration = configuration
    }
}

// MARK: - Internal Storage

final class Storage: Sendable {
    private let state: OSAllocatedUnfairLock<StorageState>

    init(configuration: AppErrorReporter.Configuration) {
        self.state = OSAllocatedUnfairLock(initialState: StorageState(configuration: configuration))
    }

    var configuration: AppErrorReporter.Configuration {
        state.withLock { $0.configuration }
    }

    func addHandler(_ handler: @escaping ErrorHandler) -> UUID {
        let id = UUID()
        state.withLock { $0.handlers[id] = handler }
        return id
    }

    func removeHandler(_ id: UUID) {
        state.withLock { _ = $0.handlers.removeValue(forKey: id) }
    }

    func setSingleHandler(_ handler: ErrorHandler?) {
        state.withLock { $0.singleHandler = handler }
    }

    func clearHandlers() {
        state.withLock {
            $0.handlers.removeAll()
            $0.singleHandler = nil
        }
    }

    func snapshotHandlers() -> (single: ErrorHandler?, multiple: [ErrorHandler], config: AppErrorReporter.Configuration) {
        state.withLock { ($0.singleHandler, Array($0.handlers.values), $0.configuration) }
    }

    func updateConfiguration(_ mutate: @Sendable (inout AppErrorReporter.Configuration) -> Void) {
        state.withLock { mutate(&$0.configuration) }
    }

    func reset() {
        state.withLock {
            $0.handlers.removeAll()
            $0.singleHandler = nil
            $0.configuration = AppErrorReporter.Configuration()
        }
    }
}

// MARK: - Internal Error Collector

struct CollectorState: Sendable {
    var errors: [AnyAppError] = []
    let maxCapacity: Int

    init(maxCapacity: Int = 1000) {
        self.maxCapacity = maxCapacity
    }
}

final class ErrorCollector: Sendable {
    private let state: OSAllocatedUnfairLock<CollectorState>

    init(maxCapacity: Int = 1000) {
        self.state = OSAllocatedUnfairLock(initialState: CollectorState(maxCapacity: maxCapacity))
    }

    var errors: [AnyAppError] {
        state.withLock { $0.errors }
    }

    func append(_ error: AnyAppError) {
        state.withLock { s in
            if s.errors.count >= s.maxCapacity {
                s.errors.removeFirst()
            }
            s.errors.append(error)
        }
    }
}
