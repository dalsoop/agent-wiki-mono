import Foundation
import WikiLedgerKit

// 공포하는 주체(작성자 종류·모델 기록·기기) 결정.
// 근거: docs/business-rules.md "작성자와 모델 기록", docs/security.md "작성자·화자 신뢰", 결정 0007.

/// 모델 기록 칸 — 코어에 들어가는 값(아는 값만).
public struct LawModelRecord: Sendable, Equatable {
    public var runtime: String?
    public var runtimeVersion: String?
    public var model: String?
    public var effort: String?
    public var app: String?
    public var appVersion: String?

    public init(
        runtime: String? = nil, runtimeVersion: String? = nil, model: String? = nil,
        effort: String? = nil, app: String? = nil, appVersion: String? = nil
    ) {
        self.runtime = runtime
        self.runtimeVersion = runtimeVersion
        self.model = model
        self.effort = effort
        self.app = app
        self.appVersion = appVersion
    }

    /// 칸마다 이 값이 없으면 `fallback` 의 값을 쓴다.
    public func filling(from fallback: LawModelRecord) -> LawModelRecord {
        func pick(_ a: String?, _ b: String?) -> String? {
            if let a, !a.trimmingCharacters(in: .whitespaces).isEmpty { return a }
            if let b, !b.trimmingCharacters(in: .whitespaces).isEmpty { return b }
            return nil
        }
        return LawModelRecord(
            runtime: pick(runtime, fallback.runtime),
            runtimeVersion: pick(runtimeVersion, fallback.runtimeVersion),
            model: pick(model, fallback.model),
            effort: pick(effort, fallback.effort),
            app: pick(app, fallback.app),
            appVersion: pick(appVersion, fallback.appVersion))
    }
}

/// 모델 기록 값을 모으는 한 자리.
/// 우선순위(business-rules): 명시 인자 > 위키 전용 환경 변수 > 실행 도구 환경 변수 > 세션 등록 파일.
/// 실행 도구 환경 변수와 세션 등록 파일 단계는 세션 훅 작업(T6)이 `collect` 안에 더한다.
public enum LawModelRecordSource {
    public static let runtimeKey = "AGENT_WIKI_RUNTIME"
    public static let modelKey = "AGENT_WIKI_MODEL"
    public static let effortKey = "AGENT_WIKI_EFFORT"
    public static let runtimeVersionKey = "AGENT_WIKI_RUNTIME_VERSION"
    public static let appKey = "AGENT_WIKI_APP"
    public static let appVersionKey = "AGENT_WIKI_APP_VERSION"

    /// 위키 전용 환경 변수의 값.
    public static func wikiEnvironment(_ environment: [String: String]) -> LawModelRecord {
        LawModelRecord(
            runtime: environment[runtimeKey], runtimeVersion: environment[runtimeVersionKey],
            model: environment[modelKey], effort: environment[effortKey],
            app: environment[appKey], appVersion: environment[appVersionKey])
    }

    /// 값을 모은다. 앞 단계에 없는 칸만 뒤 단계에서 채운다. 다른 세션을 추정하지 않는다.
    public static func collect(explicit: LawModelRecord, environment: [String: String]) -> LawModelRecord {
        explicit.filling(from: wikiEnvironment(environment))
        // T6: .filling(from: 실행 도구 환경 변수) .filling(from: 세션 등록 파일)
    }
}

public enum LawActorError: Error, Equatable, CustomStringConvertible {
    case unknownAuthorKind(String)

    public var description: String {
        switch self {
        case .unknownAuthorKind(let author):
            return "작성자 종류를 정할 수 없음: '\(author)' — --as agent:<이름>@<기기> · user:<이름> · app:<앱 슬러그>"
        }
    }
}

public enum LawActorResolution {
    /// 작성자 접두어 → 종류. `agent:` → agent, `user:` → human, `app:` → app.
    public static func kind(of author: String) -> LawAuthorKind? {
        let trimmed = author.trimmingCharacters(in: .whitespaces)
        let table: [(String, LawAuthorKind)] = [("agent:", .agent), ("user:", .human), ("app:", .app)]
        for (prefix, kind) in table where trimmed.hasPrefix(prefix) && trimmed.count > prefix.count {
            return kind
        }
        return nil
    }

    /// 공포 주체. 사람 공포는 모델 칸을 비우고(명시 인자를 주면 공포 검증이 거부한다) runtime 을 `human` 으로,
    /// 판단 없는 앱 공포는 runtime 을 `app` 으로 적는다. `device` 는 설정의 이 기기 키.
    public static func actor(
        author: String,
        explicit: LawModelRecord = LawModelRecord(),
        environment: [String: String],
        device: String?
    ) throws -> LawActor {
        let trimmed = author.trimmingCharacters(in: .whitespaces)
        guard let kind = kind(of: trimmed) else { throw LawActorError.unknownAuthorKind(author) }
        switch kind {
        case .human:
            return LawActor(
                author: trimmed, kind: .human, device: device,
                runtime: explicit.runtime ?? LawRuntime.human.rawValue,
                runtimeVersion: explicit.runtimeVersion, model: explicit.model, effort: explicit.effort)
        case .agent:
            let values = LawModelRecordSource.collect(explicit: explicit, environment: environment)
            return LawActor(
                author: trimmed, kind: .agent, device: device, runtime: values.runtime,
                runtimeVersion: values.runtimeVersion, model: values.model, effort: values.effort)
        case .app:
            let values = LawModelRecordSource.collect(explicit: explicit, environment: environment)
            return LawActor(
                author: trimmed, kind: .app, device: device,
                runtime: values.runtime ?? (values.model == nil ? LawRuntime.app.rawValue : nil),
                runtimeVersion: values.runtimeVersion, model: values.model, effort: values.effort,
                app: values.app ?? String(trimmed.dropFirst("app:".count)), appVersion: values.appVersion)
        }
    }
}
