import Foundation

/// 제품 ID 업데이트 피드 — Release Distribution v1 의 opt-in 선언과 ship 스탬프.
///
/// - **선언**: 앱 소스 `Packaging/package-identity.json` 의 `"update_feed": "product-registry"`.
///   ship(DistributionCore `ProductRegistryFeed`)과 옛 CDN 발행 도구가 같은 판독(`declaration`)을 쓴다.
/// - **스탬프**: ship 은 opt-in 앱에만 Info.plist `GujoProductID` 를 박는다. 그래서 설치본에 이 키가
///   있으면 그 빌드는 새 배포 체인의 몫이다. 옛 CDN 체인(ship 뒤 자동 발행, pending 대조, 수동 발행,
///   fleet 분류)은 이 키로 그런 설치본을 알아본다 — 릴리스 목록 정본이 둘로 갈라지지 않게.
///
/// 발행은 대개 설치본만 다룬다(공증 큐의 스테이플 경로에는 소스 디렉터리가 없다). 그래서 설치본
/// 판정은 소스 identity 를 다시 읽지 않고, ship 이 판정해 남긴 스탬프를 읽는다.
public enum ProductFeedStamp {
    public static let productIDPlistKey = "GujoProductID"
    /// package-identity.json opt-in 키와 유일한 허용 값.
    public static let identityKey = "update_feed"
    public static let optInValue = "product-registry"

    /// 앱 소스의 opt-in 선언 상태.
    public enum Declaration: Equatable, Sendable {
        /// 선언 없음 — 옛 체인 그대로.
        case none
        case productRegistry
        /// 키는 있는데 값이 허용 값이 아니다(문자열이 아니면 그 표현).
        case invalid(value: String)
        /// 키 토큰은 있는데 JSON 으로 읽히지 않는다.
        case unreadable
    }

    /// `<appDir>/Packaging/package-identity.json` 의 선언.
    ///
    /// 파일에 `"update_feed"` 토큰이 없으면 JSON 을 해석하지 않고 `.none` 이다 — 선언하지 않은
    /// 앱은 identity 가 깨져 있어도 예전처럼 옛 체인을 탄다(깨진 identity 는 lint 가 잡는다).
    public static func declaration(appDir: String) -> Declaration {
        let path = identityPath(appDir: appDir)
        guard let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8),
              text.contains("\"\(identityKey)\"") else { return .none }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            return .unreadable
        }
        guard let identity = object as? [String: Any],
              let raw = identity[identityKey] else { return .none }
        guard let value = raw as? String, value == optInValue else {
            return .invalid(value: "\(raw)")
        }
        return .productRegistry
    }

    public static func identityPath(appDir: String) -> String {
        (appDir as NSString).appendingPathComponent("Packaging/package-identity.json")
    }

    /// Info.plist 사전의 제품 ID. 없거나 0 이하면 nil.
    public static func productID(inInfoPlist dict: [String: Any]) -> Int? {
        guard let id = dict[productIDPlistKey] as? Int, id > 0 else { return nil }
        return id
    }

    /// `.app` 의 `Contents/Info.plist` 에서 읽는다. 읽을 수 없으면 스탬프가 없는 것과 같다.
    public static func productID(appBundle: String) -> Int? {
        let path = (appBundle as NSString).appendingPathComponent("Contents/Info.plist")
        guard let dict = NSDictionary(contentsOfFile: path) as? [String: Any] else { return nil }
        return productID(inInfoPlist: dict)
    }
}
