import Foundation

// 저비용 채택: 앱마다 게시할 필드를 손으로 고르지 않고, 모델을 리플렉션해 핵심 상태를
// 자동으로 뽑아 게시한다. `@Observable`(직접 저장) 모델에 특히 잘 맞고, `@Published`
// (ObservableObject)도 best-effort 로 언랩한다. 직렬화 불가 값은 건너뛴다.
//
// 채택(한 줄):
//   StateMirror.autoPublish(app: "MyApp", reflecting: model)   // 상태 바뀔 때/주기적으로
// 또는 앱이 이미 도는 타이머/onChange 에 얹는다.
public extension StateMirror {
    /// 모델을 리플렉션해 핵심 상태 요약을 게시한다(envelope: app·updatedAt·state).
    static func autoPublish(app: String, reflecting subject: Any) {
        publishJSONObject(app: app, reflectSummary(subject))
    }

    /// 모델을 얕게 리플렉션해 JSON 직렬화 가능한 요약 딕셔너리를 만든다.
    /// - 스칼라(String/Bool/정수/실수/Date/URL) → 그대로
    /// - Optional → 언랩(또는 생략), enum → case 이름, 컬렉션 → 원소 수
    /// - 그 외(중첩 객체·함수·클로저 등) → 생략
    static func reflectSummary(_ subject: Any) -> [String: Any] {
        var out: [String: Any] = [:]
        for child in Mirror(reflecting: subject).children {
            guard let raw = child.label else { continue }
            let label = raw.hasPrefix("_") ? String(raw.dropFirst()) : raw
            var value = child.value
            // @Published var x → 저장은 `_x: Published<T>` → 내부 값 언랩.
            // 단 실제 `Published<>` 래퍼일 때만 — @Observable 의 `_x` 백킹필드는 원시값을
            // 직접 담으므로(중첩 struct 포함) BFS 로 잘못 파고들면 엉뚱한 스칼라를 집는다.
            if raw.hasPrefix("_"),
               String(describing: type(of: value)).hasPrefix("Published<"),
               let inner = publishedValue(value) {
                value = inner
            }
            if let j = jsonScalar(value) { out[label] = j }
        }
        return out
    }

    /// Published<T> 등 래퍼에서 내부 스칼라 값을 best-effort 로 꺼낸다.
    /// Published 는 내부 저장이 `.value(T)`/`.publisher` enum 이라 몇 단계 파고들어야 한다 —
    /// enum/컬렉션을 스칼라로 오인하지 않게 strictScalar 로 진짜 값만 잡는다(BFS).
    private static func publishedValue(_ v: Any) -> Any? {
        var frontier: [Any] = [v]
        for _ in 0..<4 {
            var next: [Any] = []
            for item in frontier {
                for c in Mirror(reflecting: item).children {
                    if strictScalar(c.value) != nil { return c.value }
                    next.append(c.value)
                }
            }
            if next.isEmpty { break }
            frontier = next
        }
        return nil
    }

    /// enum/컬렉션을 제외한 진짜 스칼라만(Published 내부 탐색용).
    private static func strictScalar(_ value: Any) -> Any? {
        switch value {
        case is String, is Bool, is Int, is Int64, is Int32, is Double, is Float, is Date, is URL:
            return value
        default:
            return nil
        }
    }

    /// 값 하나를 JSON 직렬화 가능한 스칼라로 정규화(불가하면 nil).
    private static func jsonScalar(_ value: Any) -> Any? {
        switch value {
        case let v as String: return v
        case let v as Bool: return v
        case let v as Int: return v
        case let v as Int64: return Int(v)
        case let v as Int32: return Int(v)
        case let v as Double: return v
        case let v as Float: return Double(v)
        case let v as Date: return ISO8601DateFormatter().string(from: v)
        case let v as URL: return v.absoluteString
        default:
            let m = Mirror(reflecting: value)
            switch m.displayStyle {
            case .optional:
                return m.children.first.flatMap { jsonScalar($0.value) }
            case .enum:
                return String(describing: value)
            case .collection, .set, .dictionary:
                return m.children.count
            default:
                return nil
            }
        }
    }
}

/// 한 줄 채택용 주기 티커. App/모델에서 인스턴스를 보관만 하면 주기적으로 모델을 리플렉션해
/// 자동 게시하고, 앱 종료 시 미러를 clear 한다. @MainActor 모델을 안전하게 메인에서 읽는다.
///
/// 사용:
///   @State private var mirror: StateMirrorAutoTicker?
///   ... .task { mirror = StateMirrorAutoTicker(app: "MyApp") { model } }
@MainActor
public final class StateMirrorAutoTicker {
    private var timer: Timer?
    private let app: String
    private let snapshot: () -> Any?

    public init(app: String, interval: TimeInterval = 3, snapshot: @escaping () -> Any?) {
        self.app = app
        self.snapshot = snapshot
        StateMirror.onTerminate(app: app, .clear)
        publish()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }   // 티커가 사라지면 타이머도 정리(누수 방지)
            MainActor.assumeIsolated { self.publish() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func publish() {
        if let m = snapshot() { StateMirror.autoPublish(app: app, reflecting: m) }
    }

    public func stop() { timer?.invalidate(); timer = nil }
}
