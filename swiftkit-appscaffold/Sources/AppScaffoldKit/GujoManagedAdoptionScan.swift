import Foundation

/// 앱 디렉터리에서 채택 레코드를 조립한다.
///
/// `GujoManagedAdoption` 에 두면 파일 if/guard 와 타입 분기 합이 한도를 넘는다.
enum GujoManagedAdoptionScan {
    struct Source {
        let url: URL
        let text: String
    }

    /// 앱 하나를 읽는다. `Package.swift` 가 없으면 앱이 아니다(리소스 디렉터리 등).
    static func record(appDirectory: URL) -> GujoManagedAdoption.AppRecord? {
        let manifest = appDirectory.appendingPathComponent("Package.swift")
        guard let package = try? String(contentsOf: manifest, encoding: .utf8) else { return nil }

        let directory = appDirectory.lastPathComponent
        // 라이브러리·시뮬 코어는 Cloud Apps 소비 앱이 아니다.
        if directory.hasSuffix("-core") { return nil }
        if !GujoManagedAdoptionText.declaresExecutable(package) { return nil }

        let sources = swiftSources(under: appDirectory.appendingPathComponent("Sources"))
        let cli = cliName(appDirectory: appDirectory)
        let hasGUIApp = hasGUIApp(in: sources)
        let cliChecks = cliConsultsLedger(in: sources, cli: cli, hasGUIApp: hasGUIApp)
        // iOS 함대 앱은 GUI 에 `.gujoManaged()` 를 **걸면 안 된다**(gujo-managed.md
        // 2026-08-05 사고). 정본은 CLI 게이트(`exitIfNotEntitled*`). CLI 가 원장에
        // 물으면 managed 로 센다 — trait-only 로 밀어 에이전트가 금지된 GUI 게이트를
        // 붙이게 만들지 않는다.
        let iosCLIManaged = GujoManagedAdoptionText.isIOSFleetApp(directory: directory) && cliChecks
        // GUI 창이 없는 패키지(서버·파이프라인 CLI)는 CLI 원장 조회가 게이트다.
        let cliOnlyManaged = cliChecks && !hasGUIApp

        return GujoManagedAdoption.AppRecord(
            directory: directory,
            traitEnabled: GujoManagedAdoptionText.declaresTrait(package),
            callsGate: guiCallsGate(in: sources, cli: cli) || iosCLIManaged || cliOnlyManaged,
            cliName: cli,
            cliConsultsLedger: cliChecks,
            dependsOnLicenseKit: GujoManagedAdoptionText.declaresLicenseKitDependency(package),
            usesLegacyLicenseAPI: sources.contains {
                GujoManagedAdoptionText.sourceUsesLegacyLicenseAPI(in: $0.text)
            })
    }

    /// dual-entry CLI 이름 — `interop.json` 이 정본이다(계약 파일).
    static func cliName(appDirectory: URL) -> String? {
        let url = appDirectory.appendingPathComponent("interop.json")
        guard let data = try? Data(contentsOf: url),
              let object = ({ () -> Any? in do { return try JSONSerialization.jsonObject(with: data) } catch { return nil } }()) as? [String: Any],
              let cli = object["cli"] as? String, !cli.isEmpty
        else { return nil }
        return cli
    }

    static func swiftSources(under root: URL) -> [Source] {
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return [] }
        var out: [Source] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            out.append(Source(url: url, text: text))
        }
        return out
    }

    static func hasGUIApp(in sources: [Source]) -> Bool {
        sources.contains { src in
            GujoManagedAdoptionText.conformsToScaffold(src.text)
                || GujoManagedAdoptionText.declaresSwiftUIApp(src.text)
        }
    }

    static func cliConsultsLedger(in sources: [Source], cli: String?, hasGUIApp: Bool) -> Bool {
        sources.contains { src in
            guard GujoManagedAdoptionText.mentions("GujoManaged.exitIfNotEntitled", in: src.text)
            else { return false }
            if GujoManagedCLISource.isCLISource(src.url, cliName: cli) { return true }
            // Hummingbird 서버처럼 폴더명이 *CLI 가 아닌 유일한 executable.
            return !hasGUIApp
        }
    }

    /// 직접 부르거나, **스캐폴드 프로토콜을 쓰거나**. 후자는 `RanodeAppShell` 이
    /// 대신 걸어준다 — 앱마다 한 줄을 붙이지 않는 것이 이 시스템의 요점이라,
    /// 스캐폴드 채택을 미채택으로 세면 통일화를 거꾸로 재촉하게 된다.
    /// AppKit 진입은 View modifier 대신 `GujoManaged.status` + `handOff` 로 막는다.
    /// status/handOff 가 **CLI 소스**에만 있으면 GUI 게이트로 세지 않는다
    /// (fixture·문서 예시가 CLI 에 status 를 넣어도 macOS 를 오탐하지 않게).
    /// `exitIfNotEntitled*` 는 CLI 전용 패턴이다.
    static func guiCallsGate(in sources: [Source], cli: String?) -> Bool {
        sources.contains { src in
            if GujoManagedAdoptionText.mentions(".gujoManaged()", in: src.text)
                || GujoManagedAdoptionText.conformsToScaffold(src.text) {
                return true
            }
            if GujoManagedCLISource.isCLISource(src.url, cliName: cli) { return false }
            return GujoManagedAdoptionText.mentions("GujoManaged.status", in: src.text)
                || GujoManagedAdoptionText.mentions("GujoManaged.handOff", in: src.text)
        }
    }
}
