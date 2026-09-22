import Foundation
import StateRootKit

/// `dual_entry=helpers` 앱의 PATH CLI 가 **앱 본체의 argv 명령을 대신 실행**하게 해준다.
///
/// ## 왜 필요한가
///
/// helpers 계약은 PATH 에 GUI 바이너리를 절대 링크하지 않는다(2026-07-25 dual-entry hang).
/// 그래서 스캐폴드가 넣어주는 CLI 는 `version/help/open` 만 아는 얇은 스텁인데, 정작 앱의
/// 실제 명령(`ship`·`rollout`·`verify` …)은 **GUI 타깃의 argv 디스패치**가 소유한다.
/// 결과적으로 `app-build-manager ship …` 같은 문서화된 사용법이 PATH 에서 죽어 있고,
/// 사람과 에이전트가 `/Applications/<App>.app/Contents/MacOS/<Gui>` 를 직접 부르게 된다
/// (실측 2026-07-27: ADM·quality-auditor·swift-app-store 셋 다 이 상태였다).
///
/// 이 타입은 그 간극을 메운다 — PATH 에는 여전히 **CLI 바이너리**가 있고(계약 유지),
/// 모르는 명령이 오면 설치된 앱 본체로 **exec 해서 넘긴다**.
///
/// ## 왜 exec 인가
///
/// `Process` 로 감싸면 프로세스가 하나 더 생겨 신호·종료코드·tty 상속이 어긋난다.
/// `execv` 는 현재 프로세스를 그대로 대체하므로 파이프·리다이렉션·Ctrl-C 가 자연스럽다.
public enum DualEntryDelegate {
    /// 설치된 앱 본체(GUI 실행 파일)를 찾을 위치. 앞에서부터 먼저 찾은 것을 쓴다.
    public static func candidateRoots(home: String? = nil) -> [String] {
        let h = home ?? StateRootKit.resolveHost()
        return ["/Applications", h + "/Applications"]
    }

    /// 이 프로필이 가리키는 설치된 GUI 실행 파일 경로.
    ///
    /// 번들 이름을 모르므로 후보 루트의 `*.app` 을 훑어 `Contents/MacOS/<guiExecutableName>`
    /// 이 있는 것을 찾는다 — 번들 파일명이 표시명(공백 포함)일 수 있어 추측하지 않는다.
    public static func locateGUIExecutable(
        profile: DualEntryProfile,
        roots: [String]? = nil,
        fileManager: FileManager = .default
    ) -> String? {
        for root in roots ?? candidateRoots() {
            guard let entries = try? fileManager.contentsOfDirectory(atPath: root) else { continue }
            for entry in entries.sorted() where entry.hasSuffix(".app") {
                let candidate = "\(root)/\(entry)/Contents/MacOS/\(profile.guiExecutableName)"
                if fileManager.isExecutableFile(atPath: candidate) { return candidate }
            }
        }
        return nil
    }

    /// 이 명령을 앱 본체에 넘겨야 하는가.
    ///
    /// 스텁이 직접 처리하는 것(`help`/`version`/`open`)과 빈 호출은 넘기지 않는다.
    public static func shouldDelegate(_ command: String?, handledLocally: Set<String>) -> Bool {
        guard let command, !command.isEmpty else { return false }
        guard !command.hasPrefix("-") else { return false }
        return !handledLocally.contains(command)
    }

    /// 앱 본체로 실행을 넘긴다. 성공하면 **돌아오지 않는다**(현재 프로세스를 대체).
    ///
    /// 넘길 수 없으면(앱 미설치 등) `false` 를 돌려주고, 호출자는 기존 usage 를 보여주면 된다.
    @discardableResult
    public static func exec(
        arguments: [String],
        profile: DualEntryProfile,
        roots: [String]? = nil
    ) -> Bool {
        guard let executable = locateGUIExecutable(profile: profile, roots: roots) else { return false }
        // 앱 본체의 dual-entry 가드에게 "이건 오호출이 아니라 위임" 이라고 알린다.
        // 이 표식이 없으면 가드가 realpath 규칙으로 우리를 막는다.
        setenv(DualEntryRules.delegationMarkerKey, DualEntryRules.delegationMarkerValue, 1)
        // argv[0] 은 관례상 실행 파일 경로. 뒤에 원래 인자를 그대로 붙인다.
        let argv = [executable] + arguments
        var cStrings: [UnsafeMutablePointer<CChar>?] = argv.map { strdup($0) }
        cStrings.append(nil)
        defer { for p in cStrings where p != nil { free(p) } }
        execv(executable, &cStrings)
        // execv 가 돌아왔다면 실패다.
        return false
    }

    /// 넘기기 실패 시 사람에게 보여줄 한 줄.
    public static func unavailableMessage(profile: DualEntryProfile) -> String {
        """
        error: '\(profile.guiExecutableName)' 앱 본체를 찾지 못해 명령을 넘길 수 없다.
        앱을 먼저 설치할 것: app-build-manager ship <app> release
        """
    }
}
