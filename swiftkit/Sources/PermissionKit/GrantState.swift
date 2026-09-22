import Foundation

/// 한 권한의 부여 상태 — TCC `access.auth_value` 를 앱이 읽을 수 있는 형태로 옮긴 것.
///
/// SSOT: 이 타입은 PermissionKit 이 정본이다. mac-permissions-manager 의 매트릭스,
/// 각 앱의 자기 권한 점검이 같은 어휘를 쓰도록 여기에 둔다.
public enum GrantState: String, Sendable, Codable {
    case granted     // 허용됨 (auth_value 2)
    case denied      // 거부됨 (auth_value 0)
    case limited     // 제한적, 사진 등 (auth_value 3)
    case notSet      // 아직 결정 안 됨(TCC 항목 없음)
    case unknown     // 읽기 불가(시스템 db·권한 부족)

    /// TCC `auth_value` 문자열 → 상태. 모르는 값은 `.notSet`.
    public static func fromAuthValue(_ raw: String) -> GrantState {
        switch raw {
        case "2": return .granted
        case "3": return .limited
        case "0": return .denied
        default:  return .notSet
        }
    }
}
