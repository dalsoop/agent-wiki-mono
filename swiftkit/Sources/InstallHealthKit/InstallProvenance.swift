// CryptoKit 은 Apple 전용이다. Linux(CI native-lint 가 도는 환경)에는 없다.
// InstallHealthKit 은 어디든 빌드되어야 하므로 import 만 게이트하고
// 타입은 항상 노출한다(sha256Hex 내부에서 플랫폼 분기).
#if canImport(CryptoKit)
import CryptoKit
#endif
import Foundation
import StateRootKit

/// 설치된 CLI 가 **현재 소스에서 나온 것인가**.
///
/// ## 왜 필요한가 (근본 원인)
///
/// 이 저장소의 검사·연동은 상당수가 *설치된 바이너리*를 부른다 — 계약 lint 는 제공자
/// CLI 의 `capabilities` 를 찌르고, pre-commit 은 설치된 `agent-lint-catalog` 를 쓰고,
/// 앱 간 브리지는 PATH 의 CLI 를 실행한다. 즉 **소스가 아니라 설치본을 검사**한다.
///
/// 그런데 설치본에는 출처(provenance)가 없었다. 앱들의 `version` 은
/// `"flowlog helpers-cli 1"` 같은 **하드코딩 리터럴**이라 소스가 바뀌어도 그대로다.
/// 커밋이나 빌드시각을 담는 앱은 하나도 없었다. 그래서 "소스는 고쳤는데 설치본이 낡음"
/// 은 **탐지 불가능하게 설계**돼 있었고, 2026-07-28 하루에만 세 번 물렸다
/// (agent-lint-catalog · knowledge-base-wiki · flowlog). 매번 증상만 고쳤다.
///
/// `install-cli.sh` 가 설치 시점에 `~/.agent-ops/install-stamps/<cli>.json` 에 그 앱
/// 서브트리의 커밋을 적는다. 여기서는 그 커밋 이후 앱 소스가 더 바뀌었는지 본다.
///
/// 앱 **서브트리** 커밋을 쓰는 이유: 저장소 HEAD 와 비교하면 무관한 앱의 변경까지
/// 전부 '낡음' 이 되어 신호가 죽는다.
public struct InstallProvenance: Sendable {
    public struct Report: Sendable, Equatable {
        public let cli: String
        public let appPath: String
        /// 설치 시점에 기록된 앱 서브트리 커밋.
        public let installedCommit: String
        /// 지금 그 서브트리의 마지막 커밋.
        public let currentCommit: String
        /// 설치 시점 바이너리 해시와 지금 디스크의 해시가 다른가 — **제3자가 덮어썼다**.
        public let overwritten: Bool
        /// 설치 시점에 기록된 소스 콘텐츠 해시 (없으면 커밋 비교 폴백).
        public let installedSourceHash: String?
        /// 지금 서브트리의 소스 콘텐츠 해시.
        public let currentSourceHash: String?
        public var isStale: Bool {
            if overwritten { return true }
            // sourceHash 가 스탬프에 있으면 콘텐츠 비교 — 커밋만 바뀌고 소스가 같으면 fresh.
            if let installed = installedSourceHash, let current = currentSourceHash {
                return installed != current
            }
            // 하위호환: sourceHash 없는 옛 스탬프는 커밋 비교.
            return installedCommit != currentCommit
        }
        /// 이력에서 찾은 마지막 설치 주체 — 덮어쓴 범인을 지목하는 근거.
        public let lastCaller: String?
        public var reason: String {
            if overwritten {
                return "제3자가 덮어씀(해시 불일치)"
                    + (lastCaller.map { " · 마지막 install-cli 호출: \($0)" } ?? " · install-cli 이력 없음(다른 경로로 설치됨)")
            }
            if let installed = installedSourceHash, let current = currentSourceHash, installed != current {
                return "소스 콘텐츠가 바뀜(sourceHash 불일치)"
            }
            return "소스가 더 바뀜"
        }
    }

    public let root: String

    public init(root: String) {
        self.root = root
    }

    public static var stampDirectory: URL {
        StateRootKit.url(".agent-ops/install-stamps")
    }

    /// 스탬프가 있는 CLI 들만 본다. 스탬프가 없으면 "낡았다" 고 말할 근거가 없다 —
    /// 설치를 안 했거나 옛 `install-cli.sh` 로 깔았다는 뜻이고, 그건 별개 문제다.
    public func run() -> [Report] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: Self.stampDirectory.path) else { return [] }
        var out: [Report] = []
        for name in names.sorted() where name.hasSuffix(".json") {
            let url = Self.stampDirectory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url),
                  let obj = InstallHealthJSON.object(from: data),
                  let cli = obj["cli"] as? String,
                  let appPath = obj["appPath"] as? String,
                  let installed = obj["appCommit"] as? String
            else { continue }
            // 다른 저장소에서 깔린 스탬프는 여기서 판정하지 않는다.
            guard fm.fileExists(atPath: root + "/" + appPath) else { continue }
            let current = Self.git(["-C", root, "log", "-1", "--format=%H", "--", appPath])
            guard !current.isEmpty else { continue }
            // 해시 대조 — 스탬프만 믿으면 다른 설치기가 바이너리만 덮은 경우를 놓친다.
            var overwritten = false
            if let expected = obj["binarySHA256"] as? String, !expected.isEmpty,
               let binPath = obj["binaryPath"] as? String,
               let data = fm.contents(atPath: binPath) {
                overwritten = Self.sha256Hex(data) != expected
            }
            // 소스 콘텐츠 해시 — git 프로세스 295개 문제 없이 파일시스템만으로 판정.
            let installedSH = obj["sourceHash"] as? String
            let currentSH = Self.sourceHash(appPath: appPath, root: root)
            out.append(Report(cli: cli, appPath: appPath,
                              installedCommit: installed, currentCommit: current,
                              overwritten: overwritten,
                              installedSourceHash: installedSH,
                              currentSourceHash: currentSH,
                              lastCaller: overwritten ? Self.lastCaller(for: cli) : nil))
        }
        return out
    }

    /// append-only 이력에서 그 CLI 의 마지막 설치 기록을 찾는다. 스탬프는 다음 설치가
    /// 덮지만 이력은 남으므로, 사후에 "누가 덮었나" 를 볼 수 있는 유일한 근거다.
    static func lastCaller(for cli: String) -> String? {
        let url = stampDirectory.appendingPathComponent("history.jsonl")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        for line in text.components(separatedBy: "\n").reversed() where !line.isEmpty {
            guard let data = line.data(using: .utf8),
                  let obj = InstallHealthJSON.object(from: data),
                  obj["cli"] as? String == cli else { continue }
            let caller = (obj["caller"] as? String) ?? "?"
            let at = (obj["installedAt"] as? String) ?? "?"
            let repo = (obj["repo"] as? String) ?? "?"
            return "\(at) · repo=\((repo as NSString).lastPathComponent) · \(caller.prefix(70))"
        }
        return nil
    }

    private static let hashExtensions: Set<String> = [
        ".swift", ".strings", ".plist", ".json", ".xcassets",
        ".entitlements", ".png", ".icns",
    ]

    /// 앱 서브트리 + 공유 의존성(swiftkit) 내용을 Merkle-ish SHA256 으로 요약한다.
    /// git 프로세스를 띄우지 않고 파일시스템만 읽으므로 앱 295개를 돌아도 프로세스 폭발이 없다.
    /// swiftkit 변경도 해시에 반영되므로, 공유 라이브러리가 바뀌면 캐시가 무효화된다.
    public static func sourceHash(appPath: String, root: String) -> String? {
        #if canImport(CryptoKit)
        let fm = FileManager.default
        var outer = SHA256()
        var fileCount = 0

        // 1. 소스 파일 해싱 (앱 + swiftkit + 로컬 패키지 의존성)
        for subdir in [appPath, "swiftkit/Sources", "pulsekit/Sources", "sshkit/Sources", "swiftkit-appscaffold/Sources"] {
            let base = (root as NSString).appendingPathComponent(subdir)
            guard fm.fileExists(atPath: base),
                  let enumerator = fm.enumerator(atPath: base) else { continue }
            var paths: [String] = []
            while let rel = enumerator.nextObject() as? String {
                if hashExtensions.contains(where: { rel.hasSuffix($0) }) {
                    paths.append(subdir + "/" + rel)
                }
            }
            paths.sort()
            for rel in paths {
                let full = (root as NSString).appendingPathComponent(rel)
                guard let data = fm.contents(atPath: full) else { continue }
                let fileHash = SHA256.hash(data: data)
                outer.update(data: Data(fileHash))
                fileCount += 1
            }
        }

        // 2. Package.resolved 해싱 — 외부 의존성 버전 변경 감지
        for resolvedPath in [
            (root as NSString).appendingPathComponent(appPath + "/Package.resolved"),
            (root as NSString).appendingPathComponent("swiftkit/Package.resolved"),
        ] {
            if let data = fm.contents(atPath: resolvedPath) {
                outer.update(data: SHA256.hash(data: data).withUnsafeBytes { Data($0) })
                fileCount += 1
            }
        }

        // 3. Swift 컴파일러 버전 — Xcode 업데이트 시 캐시 무효화
        #if swift(>=6.1)
        let swiftTag = "swift-6.1+"
        #elseif swift(>=6.0)
        let swiftTag = "swift-6.0"
        #elseif swift(>=5.10)
        let swiftTag = "swift-5.10"
        #else
        let swiftTag = "swift-unknown"
        #endif
        outer.update(data: Data(swiftTag.utf8))

        guard fileCount > 0 else { return nil }
        return outer.finalize().map { String(format: "%02x", $0) }.joined()
        #else
        return nil
        #endif
    }

    /// swiftkit 은 CommandKit 에 의존하지 않는다(키트 간 결합 최소화) — git 만 직접 부른다.
    static func git(_ args: [String]) -> String {
        #if os(macOS)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { return "" }
        let watchdog = DispatchQueue(label: "install-provenance.git-watchdog")
        watchdog.asyncAfter(deadline: .now() + 20) { if p.isRunning { p.terminate() } }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        #else
        return ""
        #endif
    }

    static func sha256Hex(_ data: Data) -> String {
        #if canImport(CryptoKit)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #else
        preconditionFailure("sha256Hex 는 CryptoKit(Apple)이 필요하다 — Linux CI 는 check 만 돈다")
        #endif
    }
}
