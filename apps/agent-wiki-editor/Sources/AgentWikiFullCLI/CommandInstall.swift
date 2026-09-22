import InteropKit
import Foundation
import KnowledgeBaseWikiCore
import CommandKit
import LocalizationKit
import StateRootKit

/// CLI 자기설치 — 실행 중인 바이너리를 PATH 위치에 **원자적으로** 교체한다.
/// bash `cp` 는 실행 중 바이너리 inode 를 in-place 로 덮어써 dyld 행(2026-07-20 실측)을 낸다.
/// FileManager.replaceItem 은 임시파일→rename 이라 실행 중 프로세스는 옛 inode 를 유지, 새 호출만
/// 새 파일을 받는다 — 함정이 구조적으로 불가능. 설치 로직이 bash 가 아니라 CLI 소유(앱에 귀속).
func runInstall(arguments: [String]) {
    guard let selfURL = Bundle.main.executableURL ?? runningExecutableURL() else {
        fail("자기 바이너리 경로를 못 찾음")
    }
    // GUI 번들 바이너리를 PATH 에 심으면 dual-entry hang(에이전트가 version/list 호출할 때마다
    // AppKit 기동 → WindowServer 기아). CLI product 에서만 install 허용.
    let path = selfURL.path
    if path.contains(".app/Contents/MacOS/") || selfURL.lastPathComponent == "KnowledgeBaseWiki" {
        fail("GUI 바이너리(\(selfURL.lastPathComponent)) 로는 install 금지 — Helpers/agent-wiki install 또는 app-build-manager ship")
    }
    // 대상 결정 — 위치 인자(플래그 아닌 것) 우선, 아니면 쓸 수 있는 bin 디렉터리.
    // 함정: `install --no-studio-adopt` 를 arguments[1] 경로로 오인하면 cwd/--no-studio-adopt 에 설치됨.
    let dest: URL
    let positional = arguments.dropFirst().filter { !$0.hasPrefix("-") }
    if let pathArg = positional.first {
        dest = URL(fileURLWithPath: pathArg)
    } else {
        let candidates = [HostPlatform.homebrewBin, "/usr/local/bin",
                          StateRootKit.path(".local/bin")]
        guard let dir = candidates.first(where: {
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: $0, isDirectory: &isDir) && isDir.boolValue
                && FileManager.default.isWritableFile(atPath: $0)
        }) else { fail("쓸 수 있는 bin 디렉터리 없음(brew/usr-local/.local)") }
        dest = URL(fileURLWithPath: dir).appendingPathComponent(DualEntry.cliProductName)
    }
    do {
        // dual-entry Helpers 심링크 등: atomicInstall 이 심링크를 제거하고 실파일로 깐다.
        // (GUI 심링크만 지우던 구 가드는 postinstall 실패를 남겼다 — Helpers → Contents/Helpers.)
        try atomicInstall(from: selfURL, to: dest)
        // 설치 결과가 안전한 실 CLI 인지 검증
        guard DualEntry.isSafeCLIExecutable(dest.path) else {
            fail("install 결과 검증 실패 — \(dest.path) 가 GUI 로 resolve 됨")
        }
        // 리소스 번들도 바이너리 옆으로 — init 이 역할 템플릿(Resources/agents)을 이 번들에서 읽는다.
        installResourceBundles(besideSelf: selfURL, into: dest.deletingLastPathComponent())
        // 호환 별칭(knowledge-base-wiki, memo-citation-ledger) → 실 CLI agent-wiki (절대 GUI 가 아님)
        let aliasNames = DualEntry.profile.cliAliases
        for name in aliasNames {
            let alias = dest.deletingLastPathComponent().appendingPathComponent(name)
            do {
                try FileManager.default.removeItem(at: alias)
            } catch {
                let ns = error as NSError
                if ns.domain != NSCocoaErrorDomain || ns.code != NSFileNoSuchFileError {
                    fail("별칭 제거 실패(\(alias.path)): \(error.localizedDescription)")
                }
            }
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: dest)
        }
        try DualEntry.writeInstallStamp(version: LedgerVersion.current)
        // coding-agent surface — fail-open (PATH install already OK)
        var surfaceNote = ""
        do {
            let r = try AgentSurface.attach()
            surfaceNote = r.errors.isEmpty
                ? " · skills \(r.attached.count) attached"
                : " · skills attach partial (\(r.errors.count) err)"
        } catch {
            surfaceNote = " · skills attach skipped"
        }
        let aliasNote = aliasNames.joined(separator: ", ")
        print(CLILocalization.format("CommandInstall.print", dest.path, LedgerVersion.current, aliasNote, surfaceNote))
        // dual-entry 설치 표면 SSOT = Studio (소스 빌드는 monlith).
        // monlith ship/install 직후 PATH 가 monlith 로 돌아가므로 Studio 가 있으면 자동 adopt.
        // 환경변수: adopt 경로의 재진입 차단 (AGENT_WIKI_SKIP_STUDIO_ADOPT=1)
        let skipAdopt = arguments.contains("--no-studio-adopt")
            || ProcessInfo.processInfo.environment["AGENT_WIKI_SKIP_STUDIO_ADOPT"] == "1"
        if !skipAdopt {
            let adoptNote = runStudioDualEntryAdoptIfPresent()
            if !adoptNote.isEmpty { print(adoptNote) }
        }
    } catch { fail("install 실패: \(error)") }
}

/// Studio 앱이 있으면 `agent-wiki-studio dual-entry adopt` 실행 (fail-open).
/// 반환: 한 줄 상태 메시지(비어 있으면 Studio 없음).
private func runStudioDualEntryAdoptIfPresent() -> String {
    let studioApps = [
        "/Applications/AgentWikiStudio.app",
        "/Applications/Agent Wiki Studio.app",
    ]
    guard studioApps.contains(where: { FileManager.default.fileExists(atPath: $0) }) else {
        return ""
    }
    let studioCLI = DualEntryAdoptionResolve.studioCLIPath()
    guard let studioCLI, FileManager.default.isExecutableFile(atPath: studioCLI) else {
        return CLILocalization.string("CommandInstall.return")
    }
    var env = ProcessInfo.processInfo.environment
    env["PATH"] = "\(HostPlatform.homebrewBin):/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
    let safeResult = SafeProcessRunner.run(
        studioCLI,
        ["dual-entry", "adopt"],
        environment: env,
        timeout: 60
    )
    let out = safeResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    if safeResult.ok {
        return "studio dual-entry adopt OK" + (out.isEmpty ? "" : " · \(out.prefix(160))")
    }
    return CLILocalization.format("CommandInstall.return-2", safeResult.exitCode, out.suffix(160))
}

/// monlith 가 Studio 패키지에 링크하지 않도록 PATH/Helpers 만 해석.
private enum DualEntryAdoptionResolve {
    static func studioCLIPath() -> String? {
        let candidates = [
            HostPlatform.cliBinPath("agent-wiki-studio"),
            "/usr/local/bin/agent-wiki-studio",
            "/Applications/AgentWikiStudio.app/Contents/Helpers/agent-wiki-studio",
            "/Applications/Agent Wiki Studio.app/Contents/Helpers/agent-wiki-studio",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

/// selfURL 이 있는 디렉터리의 `*_KnowledgeBaseWikiCLI.bundle`(SPM 리소스 번들)을 대상 bin 디렉터리로 복사.
private func installResourceBundles(besideSelf selfURL: URL, into destDir: URL) {
    let fm = FileManager.default
    let srcDir = selfURL.deletingLastPathComponent()
    guard let entries = try? fm.contentsOfDirectory(at: srcDir, includingPropertiesForKeys: nil) else { return }
    for b in entries where b.pathExtension == "bundle" && b.lastPathComponent.contains("KnowledgeBaseWikiCLI") {
        let target = destDir.appendingPathComponent(b.lastPathComponent)
        do {
            try fm.removeItem(at: target)
        } catch {
            let ns = error as NSError
            if ns.domain != NSCocoaErrorDomain || ns.code != NSFileNoSuchFileError {
                fputs("warning: removeItem \(target.path): \(error.localizedDescription)\n", stderr)
            }
        }
        do {
            try fm.copyItem(at: b, to: target)
        } catch {
            fputs("warning: copyItem \(b.path) → \(target.path): \(error.localizedDescription)\n", stderr)
        }
    }
}

/// 같은 디렉터리에 임시로 복사한 뒤 rename 으로 원자 교체. in-place 덮어쓰기 회피.
///
/// 함정: dest 가 Helpers dual-entry **심링크** 이면 `replaceItemAt` 이
/// "agent-wiki doesn’t exist" 로 실패한다(ADM ship postinstall 실측).
/// 심링크·same-inode 는 먼저 제거하고 파일로 깐다.
private func atomicInstall(from src: URL, to dest: URL) throws {
    let fm = FileManager.default
    let srcReal = src.resolvingSymlinksInPath().path
    if fm.fileExists(atPath: dest.path) {
        let destReal = (dest as NSURL).resolvingSymlinksInPath?.path ?? dest.path
        // 이미 같은 바이너리(하드링크/동일 inode)면 끝
        if srcReal == destReal {
            return
        }
        // 심링크(Helpers → Contents/Helpers/agent-wiki 등)는 무조건 제거 후 실파일 설치
        if (try? fm.destinationOfSymbolicLink(atPath: dest.path)) != nil {
            try fm.removeItem(at: dest)
        }
    }
    let data = try Data(contentsOf: src)
    let tmp = dest.deletingLastPathComponent()
        .appendingPathComponent(".memo-citation-ledger.install-\(ProcessInfo.processInfo.processIdentifier)")
    try data.write(to: tmp)
    try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path)
    if fm.fileExists(atPath: dest.path) {
        // 원자 교체 — 실행 중 옛 프로세스는 옛 inode 유지(dyld 행 없음)
        _ = try fm.replaceItemAt(dest, withItemAt: tmp)
    } else {
        try fm.moveItem(at: tmp, to: dest)
    }
}

/// Bundle 경로가 없을 때 폴백 — argv[0] 절대화.
private func runningExecutableURL() -> URL? {
    let arg0 = CommandLine.arguments[0]
    if arg0.hasPrefix("/") { return URL(fileURLWithPath: arg0) }
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(arg0)
}
