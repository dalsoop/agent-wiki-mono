import InteropKit
import Foundation
import KnowledgeBaseWikiCore
import StateRootKit

/// CLI 자기설치 — 실행 중인 바이너리를 PATH 위치에 **원자적으로** 교체한다.
/// bash `cp` 는 실행 중 바이너리 inode 를 in-place 로 덮어써 dyld 행(2026-07-20 실측)을 낸다.
/// FileManager.replaceItem 은 임시파일→rename 이라 실행 중 프로세스는 옛 inode 를 유지, 새 호출만
/// 새 파일을 받는다 — 함정이 구조적으로 불가능. 설치 로직이 bash 가 아니라 CLI 소유(앱에 귀속).
private func resolveInstallDestination(arguments: [String]) -> URL {
    let positional = arguments.dropFirst().filter { !$0.hasPrefix("-") }
    if let pathArg = positional.first {
        return URL(fileURLWithPath: pathArg)
    }
    let candidates = [HostPlatform.homebrewBin, "/usr/local/bin",
                      StateRootKit.path(".local/bin")]
    guard let dir = candidates.first(where: {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: $0, isDirectory: &isDir) && isDir.boolValue
            && FileManager.default.isWritableFile(atPath: $0)
    }) else { fail("쓸 수 있는 bin 디렉터리 없음(brew/usr-local/.local)") }
    return URL(fileURLWithPath: dir).appendingPathComponent(DualEntry.cliProductName)
}

private func removeItemIfExists(_ url: URL, label: String? = nil) throws {
    do {
        try FileManager.default.removeItem(at: url)
    } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError {
        // 파일이 없으면 무시
    } catch {
        let context = label.map { "\($0)(\(url.path))" } ?? url.path
        fail("제거 실패 \(context): \(error.localizedDescription)")
    }
}

private func installAliases(dest: URL) throws {
    let aliasNames = DualEntry.profile.cliAliases
    for name in aliasNames {
        let alias = dest.deletingLastPathComponent().appendingPathComponent(name)
        try removeItemIfExists(alias, label: "별칭")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: dest)
    }
}

public func runInstall(arguments: [String]) {
    guard let selfURL = Bundle.main.executableURL ?? runningExecutableURL() else {
        fail("자기 바이너리 경로를 못 찾음")
    }
    let path = selfURL.path
    if path.contains(".app/Contents/MacOS/") || selfURL.lastPathComponent == "KnowledgeBaseWiki" {
        fail("GUI 바이너리(\(selfURL.lastPathComponent)) 로는 install 금지 — Helpers/agent-wiki install 또는 app-build-manager ship")
    }
    let dest = resolveInstallDestination(arguments: arguments)
    do {
        try atomicInstall(from: selfURL, to: dest)
        guard DualEntry.isSafeCLIExecutable(dest.path) else {
            fail("install 결과 검증 실패 — \(dest.path) 가 GUI 로 resolve 됨")
        }
        installResourceBundles(besideSelf: selfURL, into: dest.deletingLastPathComponent())
        try installAliases(dest: dest)
        try DualEntry.writeInstallStamp(version: LedgerVersion.current)
        let surfaceNote = attachSurfaceNote()
        let aliasNote = DualEntry.profile.cliAliases.joined(separator: ", ")
        print("설치: \(dest.path) (버전 \(LedgerVersion.current)) · 별칭 \(aliasNote) · stamp OK\(surfaceNote)") // allow:debug
        let skipAdopt = arguments.contains("--no-studio-adopt")
            || ProcessInfo.processInfo.environment["AGENT_WIKI_SKIP_STUDIO_ADOPT"] == "1"
        if !skipAdopt {
            let adoptNote = runStudioDualEntryAdoptIfPresent()
            if !adoptNote.isEmpty { print(adoptNote) } // allow:debug
        }
    } catch { fail("install 실패: \(error)") }
}

private func attachSurfaceNote() -> String {
    do {
        let r = try AgentSurface.attach()
        return r.errors.isEmpty
            ? " · skills \(r.attached.count) attached"
            : " · skills attach partial (\(r.errors.count) err)"
    } catch {
        return " · skills attach skipped"
    }
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
        return "tip: Studio 앱은 있으나 agent-wiki-studio 없음 → ship Studio 후 dual-entry adopt"
    }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: studioCLI)
    p.arguments = ["dual-entry", "adopt"]
    var env = ProcessInfo.processInfo.environment
    env["PATH"] = "\(HostPlatform.homebrewBin):/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
    p.environment = env
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    do {
        try p.run()
        waitWithTimeout(p, seconds: 60)
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if p.terminationStatus == 0 {
            return "studio dual-entry adopt OK" + (out.isEmpty ? "" : " · \(out.prefix(160))")
        }
        return "studio dual-entry adopt 실패(\(p.terminationStatus)): \(out.suffix(160)) — 수동: agent-wiki-studio dual-entry adopt"
    } catch {
        return "studio dual-entry adopt 실행 실패: \(error.localizedDescription)"
    }
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
    let entries: [URL]
    do { entries = try fm.contentsOfDirectory(at: srcDir, includingPropertiesForKeys: nil) } catch { return }
    for b in entries where b.pathExtension == "bundle" && b.lastPathComponent.contains("KnowledgeBaseWikiCLI") {
        let target = destDir.appendingPathComponent(b.lastPathComponent)
        do {
            try fm.removeItem(at: target)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError {
            // 파일이 없으면 무시
        } catch {
            fputs("warning: removeItem \(target.path): \(error.localizedDescription)\n", stderr)
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

private func waitWithTimeout(_ process: Process, seconds: TimeInterval = 30) {
    let src = DispatchSource.makeTimerSource()
    src.schedule(deadline: .now() + seconds)
    src.setEventHandler { process.terminate() }
    src.resume()
    process.waitUntilExit()
    src.cancel()
}

/// Bundle 경로가 없을 때 폴백 — argv[0] 절대화.
private func runningExecutableURL() -> URL? {
    let arg0 = CommandLine.arguments[0]
    if arg0.hasPrefix("/") { return URL(fileURLWithPath: arg0) }
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(arg0)
}
