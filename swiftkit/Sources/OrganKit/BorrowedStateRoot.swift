import Foundation
import StateRootKit

/// 어댑터가 **읽기만** 할 수 있는 상태 루트 + 상속 환경.
///
/// 왜 타입인가: 어댑터가 `env["SWIFT_APP_STATE_ROOT"] = …` 한 줄을 쓰면 자식 프로세스가
/// 부모와 다른 상태 루트를 본다 — 테넌트 격리가 어댑터 한 줄로 뚫린다.
/// `no-stateroot-mutation-in-adapter` 린트가 그 대입문을 텍스트로 잡아왔지만,
/// `PluginExecutionContext.makeEnvironment` 가 **가변 `[String: String]` 을 그대로
/// 돌려주는 한** 어댑터는 받은 뒤에 언제든 덮어쓸 수 있다. 린트가 못 보는 모양으로
/// 쓰면 그만이다.
///
/// 이 타입은 사전을 밖으로 내주지 않는다. 자식 환경을 만드는 문이 하나뿐이고
/// (`childEnvironment(adding:)`), 그 문이 `SWIFT_APP_STATE_ROOT` 를 **거부**한다.
/// 루트를 정하는 것은 `StateRootKit` 이지 어댑터가 아니다.
public struct BorrowedStateRoot: Sendable {
    /// `StateRootKit` 이 판정한 루트. 어댑터는 이 값을 읽을 수만 있다.
    public let path: String

    /// 상속 환경. `private` 이라 밖에서 변형할 수 없다.
    private let inherited: [String: String]

    public enum Refusal: Error, Equatable, CustomStringConvertible {
        /// 어댑터가 상태 루트 키를 직접 만들려 했다.
        case mutatesStateRoot(key: String)

        public var description: String {
            switch self {
            case .mutatesStateRoot(let key):
                return "어댑터는 '\(key)' 를 만들지 않는다 — 상속 환경을 그대로 넘기고,"
                    + " 루트 결정은 StateRootKit 이 한다"
            }
        }
    }

    public init(
        inheriting environment: [String: String] = ProcessInfo.processInfo.environment,
        resolvedBy resolver: ([String: String]) -> String = { StateRootKit.resolve(environment: $0) }
    ) {
        self.inherited = environment
        self.path = resolver(environment)
    }

    /// 상속 환경의 한 값을 읽는다. 쓰는 문은 없다.
    public func value(forKey key: String) -> String? { inherited[key] }

    /// 상속 환경에 그 키가 있는지.
    public func hasKey(_ key: String) -> Bool { inherited[key] != nil }

    /// 자식 프로세스에 넘길 환경을 만드는 **유일한** 문.
    ///
    /// `extras` 에 `SWIFT_APP_STATE_ROOT` 가 있으면 던진다 — 조용히 무시하면
    /// 부르는 쪽은 자기가 루트를 바꿨다고 믿은 채로 간다.
    public func childEnvironment(adding extras: [String: String] = [:]) throws -> [String: String] {
        let guarded = StateRootKit.declaredEnv
        if extras[guarded] != nil { throw Refusal.mutatesStateRoot(key: guarded) }
        var env = inherited
        for (k, v) in extras { env[k] = v }
        return env
    }
}
