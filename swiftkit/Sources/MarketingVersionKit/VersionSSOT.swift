import Foundation

/// 함대 마케팅 버전의 SSOT 저장소 — `Versions/<앱디렉터리>` 한 줄 파일.
///
/// plist 에서 버전을 직접 관리하던 시절의 문제(사람 손편집 125앱·main 추격 경합·
/// plist 키 파손 사고)를 끝내기 위해 버전을 한 곳으로 모은다. plist 의
/// `CFBundleShortVersionString` 은 ship 이 SSOT 에서 주입하는 **빌드 산물**이 된다.
///
/// 파일명 = `apps/<디렉터리>` 의 디렉터리(sufix 포함 slug). 줄 하나가 버전 전부.
///
/// 모노레포 원장(`<root>/Versions/`)이 없는 레포는 앱마다 `<appDir>/VERSION` 한 줄 파일을 둔다.
/// 어느 쪽인지는 레포 이름·경로가 아니라 **파일이 있는지**로만 판정한다(`sourcePath`).
public enum VersionSSOT {
    /// 앱 자기 버전 파일 — 모노레포 원장이 없는 레포의 SSOT.
    public static let appVersionFileName = "VERSION"

    public static func directory(root: String) -> String {
        (root as NSString).appendingPathComponent("Versions")
    }

    public static func url(root: String, app: String) -> String {
        (directory(root: root) as NSString).appendingPathComponent(app)
    }

    public static func appVersionPath(appDir: String) -> String {
        (appDir as NSString).appendingPathComponent(appVersionFileName)
    }

    /// SSOT 에 기록된 현재 버전. 파일이 없거나 파싱 불가면 nil.
    public static func version(root: String, app: String) -> String? {
        readVersion(atPath: url(root: root, app: app))
    }

    /// 이 앱의 버전이 기록된 파일 — 버전을 읽고 쓰는 모든 곳이 이 판정 하나를 쓴다.
    ///
    /// 우선순위: `<root>/Versions/<app>` 에 값이 있으면 그 파일, 없으면 `<appDir>/VERSION` 에 값이
    /// 있으면 그 파일. 둘 다 없으면 nil — 호출부는 기존 동작(plist 값)을 그대로 쓴다.
    /// `appDir` 이 nil 이면 원장만 본다(= `version(root:app:)` 과 같은 판정).
    public static func sourcePath(root: String, app: String, appDir: String?) -> String? {
        let ledger = url(root: root, app: app)
        if readVersion(atPath: ledger) != nil { return ledger }
        guard let appDir else { return nil }
        let local = appVersionPath(appDir: appDir)
        return readVersion(atPath: local) != nil ? local : nil
    }

    /// `sourcePath` 가 가리키는 파일의 버전.
    public static func resolvedVersion(root: String, app: String, appDir: String?) -> String? {
        sourcePath(root: root, app: app, appDir: appDir).flatMap { readVersion(atPath: $0) }
    }

    /// 버전 기록 — 부모 디렉터리 자동 생성, 원자적 쓰기.
    public static func write(root: String, app: String, version: String) throws {
        try write(toPath: url(root: root, app: app), version: version)
    }

    /// `sourcePath` 가 돌려준 파일(원장 또는 앱 `VERSION`)에 쓴다.
    public static func write(toPath path: String, version: String) throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try Data("\(version)\n".utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    private static func readVersion(atPath path: String) -> String? {
        // 파일 없음 = 미등록 앱 = 버전 없음(정상).
        guard let data = FileManager.default.contents(atPath: path),
              let raw = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
