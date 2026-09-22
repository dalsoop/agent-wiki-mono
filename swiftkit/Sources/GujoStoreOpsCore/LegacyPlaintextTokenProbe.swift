import Foundation
import StateRootKit

/// 옛 평문 토큰 파일 **존재만** 본다. 내용은 인증 경로에서 읽지 않는다.
///
/// 가져오기는 GUI 표준 프롬프트가 `LegacyStaffTokenImporter` 로만 한다.
public enum LegacyPlaintextTokenProbe: Sendable {
    public static let storeOpsRelativePath = ".gujo-store-ops/token"
    public static let skillStoreRelativePath = ".gujo-skill-store/token"

    public static func exists(at path: String, fileManager: FileManager) -> Bool {
        var isDir: ObjCBool = false
        let found = fileManager.fileExists(atPath: path, isDirectory: &isDir)
        return found && !isDir.boolValue
    }

    public static func storeOpsPath() -> String {
        StateRootKit.path(storeOpsRelativePath)
    }

    public static func skillStorePath() -> String {
        StateRootKit.path(skillStoreRelativePath)
    }
}
