import Foundation

/// 함대 마케팅 버전의 SSOT 저장소 — `Versions/<앱디렉터리>` 한 줄 파일.
///
/// plist 에서 버전을 직접 관리하던 시절의 문제(사람 손편집 125앱·main 추격 경합·
/// plist 키 파손 사고)를 끝내기 위해 버전을 한 곳으로 모은다. plist 의
/// `CFBundleShortVersionString` 은 ship 이 SSOT 에서 주입하는 **빌드 산물**이 된다.
///
/// 파일명 = `apps/<디렉터리>` 의 디렉터리(sufix 포함 slug). 줄 하나가 버전 전부.
public enum VersionSSOT {
    public static func directory(root: String) -> String {
        (root as NSString).appendingPathComponent("Versions")
    }

    public static func url(root: String, app: String) -> String {
        (directory(root: root) as NSString).appendingPathComponent(app)
    }

    /// SSOT 에 기록된 현재 버전. 파일이 없거나 파싱 불가면 nil.
    public static func version(root: String, app: String) -> String? {
        let path = url(root: root, app: app)
        let raw: String
        do {
            raw = try String(contentsOfFile: path, encoding: .utf8)
        } catch {
            return nil  // 미등록 앱 = 버전 없음(정상)
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 버전 기록 — 부모 디렉터리 자동 생성, 원자적 쓰기.
    public static func write(root: String, app: String, version: String) throws {
        let dir = directory(root: root)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = url(root: root, app: app)
        try Data("\(version)\n".utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    /// SSOT 에 등록된 앱 전체 — ` Versions` 디렉터리의 파일 목록.
    public static func apps(root: String) -> [String] {
        let dir = directory(root: root)
        let items = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        return items.filter { !$0.hasPrefix(".") }.sorted()
    }

    /// plist 버전과 SSOT 버전이 어긋났는지 — ship 주입·게이트가 공유하는 판정.
    /// SSOT 파일이 없으면 nil(레거시 앱 — 판정 대상 아님).
    public static func drift(root: String, app: String, plistVersion: String) -> Bool? {
        guard let ssot = version(root: root, app: app) else { return nil }
        return ssot != plistVersion
    }
}
