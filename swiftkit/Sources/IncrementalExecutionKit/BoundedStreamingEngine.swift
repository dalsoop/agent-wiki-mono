import Foundation

/// Swift Concurrency TaskGroup 기반 Bounded 병렬 스트리밍 엔진.
///
/// 1. `ProcessInfo.processInfo.activeProcessorCount` 기반 동적 가용 코어 분산.
/// 2. Bounded In-Flight 제어: 동시 실행 작업 수를 제한하여 대규모 파일셋(수만 개) 처리 시 메모리 폭증(OOM) 방지.
/// 3. 완료 즉시 결과를 수집하고 다음 작업을 공급하여 워커 간 꼬리 지연(tail latency) 해소.
public enum BoundedStreamingEngine {

    /// 시스템 UI 및 타 프로세스를 방해하지 않는 기본 안전 동시성 상한 (코어 수 / 2 ~ 전체 코어 수)
    public static var defaultConcurrencyLimit: Int {
        let count = ProcessInfo.processInfo.activeProcessorCount
        return max(2, min(16, count))
    }

    /// 제네릭 항목 배열에 대해 동시성 상한을 지키며 비동기 스트리밍 변환(Map)을 수행한다.
    public static func map<T: Sendable, R: Sendable>(
        items: [T],
        concurrencyLimit: Int = defaultConcurrencyLimit,
        transform: @escaping @Sendable (T) async throws -> R
    ) async throws -> [R] {
        guard !items.isEmpty else { return [] }
        if items.count == 1 {
            return [try await transform(items[0])]
        }

        let limit = max(1, concurrencyLimit)
        var results: [R] = []
        results.reserveCapacity(items.count)

        try await withThrowingTaskGroup(of: R.self) { group in
            var itemIterator = items.makeIterator()

            // 1. 초기 윈도우 채우기 (최대 limit개)
            var inFlight = 0
            while inFlight < limit, let nextItem = itemIterator.next() {
                inFlight += 1
                group.addTask {
                    try await transform(nextItem)
                }
            }

            // 2. 작업이 1개 완료될 때마다 새 작업 공급 (Bounded Streaming)
            while let result = try await group.next() {
                results.append(result)
                if let nextItem = itemIterator.next() {
                    group.addTask {
                        try await transform(nextItem)
                    }
                }
            }
        }

        return results
    }

    /// 실패한 작업은 무시하고 성공한 결과만 수집하는 Non-throwing 스트리밍 변환.
    public static func compactMap<T: Sendable, R: Sendable>(
        items: [T],
        concurrencyLimit: Int = defaultConcurrencyLimit,
        transform: @escaping @Sendable (T) async -> R?
    ) async -> [R] {
        guard !items.isEmpty else { return [] }

        let limit = max(1, concurrencyLimit)
        var results: [R] = []
        results.reserveCapacity(items.count)

        await withTaskGroup(of: R?.self) { group in
            var itemIterator = items.makeIterator()

            var inFlight = 0
            while inFlight < limit, let nextItem = itemIterator.next() {
                inFlight += 1
                group.addTask {
                    await transform(nextItem)
                }
            }

            while let result = await group.next() {
                if let value = result {
                    results.append(value)
                }
                if let nextItem = itemIterator.next() {
                    group.addTask {
                        await transform(nextItem)
                    }
                }
            }
        }

        return results
    }
}
