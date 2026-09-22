import Foundation

/// 시스템 UI(Cursor, 터미널, WindowServer 등)를 방해하지 않는 안전한 병렬 배치 실행 유틸리티.
///
/// `DispatchQueue.concurrentPerform`을 날것으로 쓰면 현재 스레드의 QoS를 상속받아
/// 모든 코어(P-Core 포함)를 100% 점유해 Mac 전체 UI가 버벅이는 현상을 방지한다.
/// 기본적으로 `.utility` QoS와 가용 코어의 절반(Safety Cap)을 사용하여 E-Core 위주로 작업을 분산한다.
public enum ThrottledParallel {

    /// 기본 안전 동시성 상한 (코어 수 / 2, 최소 2, 최대 8)
    public static var defaultSafeConcurrency: Int {
        let count = ProcessInfo.processInfo.activeProcessorCount
        return max(2, min(8, count / 2))
    }

    /// 배열 항목들에 대해 스레드 안전하게 병렬 변환(Map)을 수행한다.
    ///
    /// - Parameters:
    ///   - items: 처리할 입력 배열
    ///   - qos: 작업 QoS (기본 `.utility`)
    ///   - maxConcurrency: 최대 동시 실행 스레드 수 (기본 `defaultSafeConcurrency`)
    ///   - transform: 각 항목 변환 클로저
    /// - Returns: 변환된 결과 배열 (입력 순서 보장)
    public static func map<T: Sendable, R: Sendable>(
        _ items: [T],
        qos: DispatchQoS.QoSClass = .utility,
        maxConcurrency: Int = defaultSafeConcurrency,
        transform: @escaping @Sendable (T) -> R
    ) -> [R] {
        guard !items.isEmpty else { return [] }
        if items.count == 1 {
            return [transform(items[0])]
        }

        let total = items.count
        let concurrency = max(1, min(maxConcurrency, total))

        // 결과 슬롯은 락으로 감싼다 — 여러 스레드가 배열의 서로 다른 인덱스에 동시에
        // 쓰는 것도 Swift 배열에서는 데이터 레이스다.
        let storage = LockedState<[R?]>(Array(repeating: nil, count: total))
        let queue = DispatchQueue.global(qos: qos)
        let group = DispatchGroup()
        let semaphore = DispatchSemaphore(value: concurrency)

        for (index, item) in items.enumerated() {
            semaphore.wait()
            group.enter()
            queue.async {
                let res = transform(item)
                storage.withLock { $0[index] = res }
                semaphore.signal()
                group.leave()
            }
        }

        group.wait()
        return storage.withLock { $0 }.compactMap { $0 }
    }

    /// 배열 항목들에 대해 nil이 아닌 결과만 모아서 반환한다 (compactMap).
    public static func compactMap<T: Sendable, R: Sendable>(
        _ items: [T],
        qos: DispatchQoS.QoSClass = .utility,
        maxConcurrency: Int = defaultSafeConcurrency,
        transform: @escaping @Sendable (T) -> R?
    ) -> [R] {
        map(items, qos: qos, maxConcurrency: maxConcurrency, transform: transform).compactMap { $0 }
    }

    /// 배열 항목들에 대해 스레드 안전하게 병렬 반복(forEach)을 수행한다.
    public static func forEach<T: Sendable>(
        _ items: [T],
        qos: DispatchQoS.QoSClass = .utility,
        maxConcurrency: Int = defaultSafeConcurrency,
        body: @escaping @Sendable (T) -> Void
    ) {
        guard !items.isEmpty else { return }
        if items.count == 1 {
            body(items[0])
            return
        }

        let concurrency = max(1, min(maxConcurrency, items.count))
        let queue = DispatchQueue.global(qos: qos)
        let group = DispatchGroup()
        let semaphore = DispatchSemaphore(value: concurrency)

        for item in items {
            semaphore.wait()
            group.enter()
            queue.async {
                body(item)
                semaphore.signal()
                group.leave()
            }
        }

        group.wait()
    }

    /// 정수 인덱스 범위에 대해 병렬 반복을 수행한다 (iterations 기반).
    public static func perform(
        iterations: Int,
        qos: DispatchQoS.QoSClass = .utility,
        maxConcurrency: Int = defaultSafeConcurrency,
        _ block: @escaping @Sendable (Int) -> Void
    ) {
        guard iterations > 0 else { return }
        let items = Array(0..<iterations)
        forEach(items, qos: qos, maxConcurrency: maxConcurrency, body: block)
    }
}
