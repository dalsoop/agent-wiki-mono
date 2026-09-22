import Foundation

/// 앱이 **필요한 권한을 한 곳에** 선언한다. 온보딩·doctor·CLI 가 같은 선언을 읽는다.
///
/// 왜 필요한가 (실측 2026-08-07~08): 온보딩 화면은 자기가 요청할 권한 목록을 코드에
/// 하드코딩하고, doctor 는 TCC 원장에 **이미 등록된** 것만 보고, 상태 CLI 는 또 다른
/// 목록을 갖고 있었다. 그래서 "온보딩에서 요청하는데 doctor 는 모르는" 권한과
/// "doctor 가 죽었다고 하는데 앱은 안 쓰는" 권한이 동시에 생겼다. 선언이 한 곳에 있으면
/// 그 어긋남이 구조적으로 불가능해진다.
///
/// 선언 위치는 앱 번들의 `Info.plist` 다 — 빌드 없이 읽히므로 함대 전수 점검
/// (`doctor`, 설치 게이트, lint)이 소스를 컴파일하지 않고 "이 앱이 무엇을 요구하는가" 를
/// 알 수 있다. Swift 상수로 두면 앱 안에서만 보인다.
///
/// ```xml
/// <key>SwiftAppRequiredPermissions</key>
/// <array>
///     <string>screenRecording</string>
///     <string>accessibility</string>
/// </array>
/// ```
///
/// 선택 권한은 `SwiftAppOptionalPermissions` 에 둔다 — 없어도 앱이 도는 기능용이라
/// doctor 가 critical 로 올리지 않는다.
public enum PermissionRequirements {

    public static let requiredKey = "SwiftAppRequiredPermissions"
    public static let optionalKey = "SwiftAppOptionalPermissions"

    public struct Declaration: Sendable, Equatable {
        public let required: [Permission]
        public let optional: [Permission]
        /// plist 에 있었지만 아는 이름이 아닌 값 — 조용히 버리지 않는다(오타가 곧 미요청이다).
        public let unknown: [String]

        public init(required: [Permission], optional: [Permission], unknown: [String] = []) {
            self.required = required
            self.optional = optional
            self.unknown = unknown
        }

        public var isEmpty: Bool { required.isEmpty && optional.isEmpty }
        /// 온보딩이 순회할 순서 — 필수 먼저.
        public var all: [Permission] { required + optional }
    }

    /// 실행 중인 앱 자신의 선언.
    public static func declared(bundle: Bundle = .main) -> Declaration {
        parse(required: bundle.object(forInfoDictionaryKey: requiredKey),
              optional: bundle.object(forInfoDictionaryKey: optionalKey))
    }

    /// 임의 `Info.plist` 의 선언 — 설치본·소스 트리를 밖에서 훑을 때(doctor·게이트) 쓴다.
    public static func declared(infoPlistPath: String) -> Declaration? {
        guard let data = FileManager.default.contents(atPath: infoPlistPath),
              let plist = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any]
        else { return nil }
        return parse(required: plist[requiredKey], optional: plist[optionalKey])
    }

    static func parse(required: Any?, optional: Any?) -> Declaration {
        var unknown: [String] = []
        func permissions(_ raw: Any?) -> [Permission] {
            guard let names = raw as? [String] else { return [] }
            var out: [Permission] = []
            for name in names {
                if let permission = Permission(declaredName: name) {
                    // 중복 선언은 온보딩에서 같은 프롬프트를 두 번 띄운다.
                    if !out.contains(permission) { out.append(permission) }
                } else {
                    unknown.append(name)
                }
            }
            return out
        }
        let req = permissions(required)
        // 필수에 이미 있으면 선택에서 뺀다 — 둘 다면 필수가 이긴다.
        let opt = permissions(optional).filter { !req.contains($0) }
        return Declaration(required: req, optional: opt, unknown: unknown)
    }
}

public extension Permission {
    /// plist·CLI·JSON 에서 쓰는 안정 이름. `TCCService` 의 rawValue 와 같은 표기를 쓴다 —
    /// 두 축이 다른 문자열을 쓰면 선언과 원장을 사람이 눈으로 맞춰야 한다.
    var declaredName: String { tccService.rawValue }

    /// 별칭도 받는다: kebab-case(CLI 관행)와 TCC 데이터베이스 키(원장에서 복붙).
    init?(declaredName raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if let service = TCCService(rawValue: trimmed),
           let permission = service.runtimePermission {
            self = permission
            return
        }
        if let service = TCCService(tccKey: trimmed) ?? TCCService(tccDatabaseKey: trimmed),
           let permission = service.runtimePermission {
            self = permission
            return
        }
        // screen-recording → screenRecording
        let camel = trimmed.split(separator: "-").enumerated().map { index, part in
            index == 0 ? String(part) : part.capitalized
        }.joined()
        if let service = TCCService(rawValue: camel), let permission = service.runtimePermission {
            self = permission
            return
        }
        return nil
    }
}
