import Foundation

/// 레포의 앱 하나에서 판정에 필요한 사실(파일 읽기 결과를 담는 값 타입 — IO 는 호출부가 한다).
public struct RepoApp: Equatable, Sendable {
    public let directory: String
    /// `Packaging/Info.plist` 의 `CFBundleName`(설치 이름의 정본). 없으면 nil.
    public let bundleName: String?
    /// `scripts/install-app.sh` 원문. 없으면 nil.
    public let installScript: String?
    /// `scripts/make-app.sh` 원문. 없으면 nil.
    public let makeScript: String?

    public init(directory: String, bundleName: String?, installScript: String?, makeScript: String?) {
        self.directory = directory
        self.bundleName = bundleName
        self.installScript = installScript
        self.makeScript = makeScript
    }
}

/// 레포 소스 판정 — 커밋 게이트(scripts/lint-install-health.sh)가 쓴다.
///
/// 두 가지를 잡는다:
/// 1. install-app.sh 가 이름을 하드코딩해 Info.plist(정본)와 어긋남 → 구·신 번들 공존의 공장.
/// 2. 확장(.appex)·Helper 를 심는 앱인데 공용 위임 shim → 확장이 조용히 빠진 채 설치됨.
public struct RepoAudit: Sendable {
    public init() {}

    /// make-app.sh 가 확장·Helper 를 심는가(= 공용 빌드로는 못 만든다 → shim 금지).
    public static func buildsExtensions(_ makeScript: String) -> Bool {
        let markers = ["appex", "PlugIns", "LaunchServices/", "XPCServices"]
        return markers.contains { makeScript.contains($0) }
    }

    /// 공용 스크립트로 위임하는 shim 인가.
    ///
    /// 주석은 세지 않는다 — 커스텀 스크립트가 "공용 install-macos-app.sh 로 위임하지 않는다" 처럼
    /// 이유를 적어두는 게 정상이라, 단순 문자열 포함으로 보면 그걸 shim 으로 오인한다(실측 오탐).
    public static func isShim(_ installScript: String) -> Bool {
        installScript.split(separator: "\n").contains { line in
            let code = line.prefix { $0 != "#" }
            return code.contains("install-macos-app.sh")
        }
    }

    /// install-app.sh 가 하드코딩한 설치 번들 이름(있으면). `DEST="$DEST_ROOT/<이름>.app"` 형태.
    public static func hardcodedBundleName(_ installScript: String) -> String? {
        let pattern = #"DEST="\$(?:DEST_ROOT|INSTALL_ROOT)/([^"$]+)\.app""#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: installScript, range: NSRange(installScript.startIndex..., in: installScript)),
              let r = Range(m.range(at: 1), in: installScript)
        else { return nil }
        return String(installScript[r])
    }

    public func audit(_ app: RepoApp) -> [HealthIssue] {
        guard let install = app.installScript else { return [] }
        var issues: [HealthIssue] = []
        let shim = Self.isShim(install)

        // 1. shim 이면 이름·경로를 Info.plist 에서 뽑으므로 불일치가 원천적으로 없다.
        if !shim, let want = app.bundleName, let got = Self.hardcodedBundleName(install), want != got {
            issues.append(HealthIssue(
                kind: .installScriptDivergence,
                severity: .warning,
                subject: app.directory,
                detail: "install-app.sh 가 '\(got).app' 으로 설치하는데 Info.plist 정본은 '\(want)' 다 — 구·신 번들이 공존하게 된다.",
                remedy: "공용 scripts/install-macos-app.sh 로 위임하는 shim 으로 바꾼다(이름은 CFBundleName 이 정본).",
                isAutoFixable: false
            ))
        }

        // 2. 확장을 심는 앱이 shim 이면 확장이 조용히 빠진다.
        if shim, let make = app.makeScript, Self.buildsExtensions(make) {
            issues.append(HealthIssue(
                kind: .shimDropsExtension,
                severity: .error,
                subject: app.directory,
                detail: "make-app.sh 가 확장(.appex)·Helper 를 심는데 install-app.sh 는 공용 위임 shim 이다 — 공용 빌드는 확장을 안 만든다.",
                remedy: "이 앱은 shim 금지 — 자체 make-app.sh 를 쓰는 커스텀 install-app.sh 를 유지한다.",
                isAutoFixable: false
            ))
        }

        return issues
    }

    public func audit(_ apps: [RepoApp]) -> [HealthIssue] {
        apps.sorted { $0.directory < $1.directory }.flatMap(audit)
    }
}
