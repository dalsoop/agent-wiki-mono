import Foundation

/// **이 바이너리가 어느 소스로 만들어졌는지 자기가 신고한다.**
///
/// 왜 필요한가 — 2026-08-10 하루에 같은 사고가 네 번 났다:
///  - `agent-lint-catalog`: 설치본에 규칙 하나가 없어 위반이 있는데도 `✓ OK` (검사 안 함이 통과로 보임)
///  - `app-build-manager`: 이미 머지된 ship 루트 수정이 설치본엔 없어 worktree ship 이 계속 실패(2회)
///  - `app-fleet-quality-auditor`: 하루 전 바이너리가 이미 고쳐진 결함 19건을 계속 보고 → 백로그 오염
///
/// 셋 다 **도구가 거짓말한 게 아니라 낡은 도구가 옛 진실을 말한 것**이고, 공통점은
/// 그 사실을 아무도 안 알려줬다는 것이다. 설치 시점에 `SASource*` 스탬프로 커밋·브랜치가
/// 이미 박혀 있는데 읽는 쪽이 없었다.
///
/// 이 타입은 그 스탬프를 읽어 **한 줄 경고**를 만든다. 판정은 순수 함수라 git 없이 검증된다.
public enum InstallStampFreshness {
    /// 설치 시점에 번들에 박히는 출처 스탬프.
    public struct Stamp: Sendable, Equatable {
        public var commit: String?
        public var branch: String?
        public var dirty: Bool
        public var sourceRoot: String?
        /// 앱 소스 디렉터리(`apps/<name>-swift`). `sourceRoot` 는 repo 루트다.
        public var sourceDirectory: String?

        public init(commit: String?, branch: String?, dirty: Bool, sourceRoot: String?,
                    sourceDirectory: String? = nil) {
            self.commit = commit
            self.branch = branch
            self.dirty = dirty
            self.sourceRoot = sourceRoot
            self.sourceDirectory = sourceDirectory
        }

        /// 실행 중인 번들에서 읽는다. CLI 가 `.app/Contents/Helpers/` 에 있어도
        /// `Bundle.main` 은 그 앱 번들이라 같은 plist 를 본다.
        public static func fromRunningBundle(_ bundle: Bundle = .main) -> Stamp {
            var info: [String: Any] = [:]
            for key in stampKeys {
                if let value = bundle.object(forInfoDictionaryKey: key) {
                    info[key] = value
                }
            }
            return fromInfoDictionary(info)
        }

        /// 이미 연 Info.plist 딕셔너리. 자기 번들이든 남의 설치본이든 키 해석은 여기만 한다.
        public static func fromInfoDictionary(_ info: [String: Any]) -> Stamp {
            func string(_ key: String) -> String? {
                (info[key] as? String).flatMap { $0.isEmpty ? nil : $0 }
            }
            let dirty = (info["SASourceDirty"] as? Bool)
                ?? (string("SASourceDirty").map { $0 == "true" || $0 == "1" } ?? false)
            return Stamp(
                commit: string("SASourceCommit"),
                branch: string("SASourceBranch"),
                dirty: dirty,
                sourceRoot: string("SASourceRoot"),
                sourceDirectory: string("SASourceDirectory")
            )
        }

        /// 디스크의 다른 앱 `Info.plist`. 실행 중 번들이 아니면 이쪽.
        public static func fromInfoPlist(at url: URL) -> Stamp? {
            guard let info = NSDictionary(contentsOf: url) as? [String: Any] else { return nil }
            return fromInfoDictionary(info)
        }
    }

    /// 스탬프된 커밋을 정본(origin/main)과 대조한 결과. git 호출은 호출측이 주입한다.
    public struct Lineage: Sendable, Equatable {
        /// 스탬프 커밋이 origin/main 에 포함되는가(=머지된 코드인가).
        public var mergedIntoMain: Bool
        /// origin/main 이 스탬프 커밋보다 몇 커밋 앞서는가. 모르면 nil.
        public var behindCount: Int?

        public init(mergedIntoMain: Bool, behindCount: Int?) {
            self.mergedIntoMain = mergedIntoMain
            self.behindCount = behindCount
        }
    }

    /// 경고 한 줄. `nil` 이면 조용히 있는다 — **정상일 때 시끄러우면 아무도 안 읽는다.**
    ///
    /// - Parameters:
    ///   - tool: 사람이 읽을 도구 이름(경고문에 박힌다).
    ///   - staleThreshold: 이 수보다 더 뒤처지면 경고. 몇 커밋 차이는 정상 흐름이라
    ///     매번 경고하면 우회가 습관이 된다(이 레포는 분 단위로 머지된다).
    public static func warning(
        tool: String,
        stamp: Stamp,
        lineage: Lineage?,
        staleThreshold: Int = 30
    ) -> String? {
        // 스탬프가 아예 없으면 판정 불가 — 조용히 넘어간다(옛 설치본·비-ADM 설치).
        guard stamp.commit != nil || stamp.branch != nil else { return nil }

        var reasons: [String] = []
        if stamp.dirty {
            reasons.append("커밋 안 된 변경 위에서 빌드됨 — 이 바이너리의 소스를 재현할 수 없다")
        }
        if let lineage, !lineage.mergedIntoMain {
            let branch = stamp.branch.map { " (\($0))" } ?? ""
            reasons.append("main 에 머지되지 않은 브랜치 소스로 설치됨\(branch)")
        }
        if let behind = lineage?.behindCount, behind > staleThreshold {
            reasons.append("정본보다 \(behind)커밋 뒤처진 소스로 설치됨")
        }
        guard !reasons.isEmpty else { return nil }

        let head = "⚠ \(tool) 설치본이 정본과 다릅니다 — 이 출력의 판단 근거가 낡았을 수 있습니다."
        let body = reasons.map { "  · \($0)" }.joined(separator: "\n")
        let fix = "  고치기: app-build-manager install <앱디렉터리>  (정본 워크트리에서)"
        return ([head] + [body, fix]).joined(separator: "\n")
    }

    fileprivate static let stampKeys = [
        "SASourceCommit", "SASourceBranch", "SASourceDirty",
        "SASourceRoot", "SASourceDirectory",
    ]

    /// 실행 중 바이너리를 판정해 **stderr 로** 한 줄 낸다. stdout 은 계약 출력이라 건드리지 않는다.
    ///
    /// `AGENT_TOOL_FRESHNESS=0` 으로 끌 수 있다(파이프라인에서 소음을 없앨 때).
    /// git 조회는 호출측이 넘긴다 — 이 kit 은 프로세스를 띄우지 않는다.
    @discardableResult
    public static func reportToStandardError(
        tool: String,
        stamp: Stamp = .fromRunningBundle(),
        lineage: Lineage?,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        write: (String) -> Void = { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
    ) -> String? {
        if let flag = environment["AGENT_TOOL_FRESHNESS"], flag == "0" || flag.lowercased() == "off" {
            return nil
        }
        guard let line = warning(tool: tool, stamp: stamp, lineage: lineage) else { return nil }
        write(line)
        return line
    }
}
