import Foundation

/// 설치된 앱이 **아이콘을 눌러도 안 뜨는** 상태를 잡는다.
///
/// dual-entry 앱은 `DualEntryRules.exitIfMisusedFromIdentity()` 로 "GUI 를 CLI 이름으로
/// 호출했는가" 를 판정하는데, 번들의 `CFBundleExecutable` 이 CLI 이름이면 **정상 실행조차
/// argv0 가 CLI 이름이라 즉시 종료된다**. 빌드·서명·설치는 전부 통과하므로 실행해 보기
/// 전에는 드러나지 않는다(실측 2026-07-28: app-fleet-quality-auditor 가 이 상태였다).
///
/// **번들만으로는 가드 호출 여부를 알 수 없다** — DualEntryKit 을 링크만 해도 메시지
/// 문자열은 바이너리에 남는다(실측: design-system-studio 는 이름이 겹쳐도 정상 실행).
/// 그래서 여기서는 warn 이고, 소스를 보는 auditor 가 fail 로 확정한다.
public struct LaunchContractProvider: DoctorProvider {
    public let id = "launch-contract"

    private let applicationsDirectory: URL

    public init(applicationsDirectory: URL = URL(fileURLWithPath: "/Applications")) {
        self.applicationsDirectory = applicationsDirectory
    }

    // FileManager 는 Sendable 이 아니라 저장하지 않고 호출 시점에 얻는다.
    private var fileManager: FileManager { .default }

    public func run() async -> [DoctorFinding] {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: applicationsDirectory,
            includingPropertiesForKeys: nil
        ) else { return [] }

        return entries
            .filter { $0.pathExtension == "app" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap(finding(for:))
    }

    /// 번들 하나를 검사한다. 문제가 없으면 nil.
    package func finding(for bundle: URL) -> DoctorFinding? {
        let contents = bundle.appendingPathComponent("Contents")
        guard
            let identityData = try? Data(
                contentsOf: contents.appendingPathComponent("Resources/package-identity.json")
            ),
            let identity = ProbeJSON.object(from: identityData),
            let mode = identity["dual_entry"] as? String,
            mode == "helpers" || mode == "cli-only",
            let plistData = try? Data(contentsOf: contents.appendingPathComponent("Info.plist"))
        else { return nil }

        let plist: [String: Any]
        do {
            guard let obj = try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else { return nil }
            plist = obj
        } catch {
            return nil
        }
        guard let executable = plist["CFBundleExecutable"] as? String else { return nil }

        // 가드가 CLI 로 판정하는 이름들 — 이 중 하나가 GUI 실행 파일명이면 즉시 종료된다.
        let cliNames = ["cli", "program", "cli_product"]
            .compactMap { identity[$0] as? String }
        guard cliNames.contains(executable) else { return nil }

        let gui = identity["gui_product"] as? String ?? "<gui_product>"
        return DoctorFinding(
            category: .install,
            severity: .warn,
            body: .init(
                subject: bundle.lastPathComponent,
                title: "GUI 실행 파일명이 CLI 이름과 같습니다",
                detail: "CFBundleExecutable=\(executable) 이(가) CLI 이름과 같습니다. 이 앱이 "
                + "DualEntryRules 가드를 호출하면 정상 실행조차 'CLI 오용' 으로 판정돼 "
                + "아이콘을 눌러도 뜨지 않습니다(실측 사례 있음). 번들만으로는 가드 호출 "
                + "여부를 알 수 없어 경고로 보고하며, 소스 기준 확정 판정은 "
                + "app-fleet-quality-auditor 의 source.launch-contract 가 한다.",
                remedy: "Packaging/Info.plist 의 CFBundleExecutable 을 gui_product(\(gui))로 바꾸고 다시 ship 하세요."
            ),
            source: id,
            payload: ["executable": executable, "guiProduct": gui, "dualEntry": mode]
        )
    }
}
