import StateRootKit
import DoctorContract
import Foundation
import InteropKit

/// **앱이 자기 자신을 진단한다** — 공용 provider 세트.
///
/// 왜 provider 인가: 오늘(2026-08-11) 검사를 여섯 갈래로 만들었는데 전부 다른 명령,
/// 다른 출력, 다른 종료코드였다. 함대를 한 장으로 볼 방법이 없었고, 보고할 때마다
/// 명령을 여섯 번 따로 돌렸다. **룰을 더할 때 함수에 if 를 박으면 그 함수가 쓰레기통이
/// 된다** — 꽂는 자리를 만들고 스키마를 하나로 둔다.
///
/// 여기 있는 provider 는 **저자가 필요 없다.** `HelpersDomainCLI.doctor` 를 부르는
/// 171개 앱이 코드 한 줄 없이 같은 검사를 받는다. 앱 고유 검사는 뒤에 덧붙인다.
public enum AppSelfDoctor {

    /// 모든 앱에 공통으로 도는 것.
    public static func standardProviders(
        cliName: String,
        appKey: String
    ) -> [any DoctorProvider] {
        [
            PathBinaryProvider(cliName: cliName),
            ResourceBundleProvider(cliName: cliName),
            StateMirrorProvider(appKey: appKey),
            CLIMarketingVersionProvider(cliName: cliName),
        ]
    }

    public static func scan(
        cliName: String,
        appKey: String,
        extra: [any DoctorProvider] = []
    ) async -> DoctorReport {
        await DoctorOrchestrator(
            providers: standardProviders(cliName: cliName, appKey: appKey) + extra
        ).scan()
    }
}

/// PATH 에 실행 가능한 진입점이 있나.
public struct PathBinaryProvider: DoctorProvider {
    public let id = "path-binary"
    private let cliName: String
    /// `FileManager` 는 Sendable 이 아니라 저장하지 않는다 — 테스트가 갈아 끼울 수
    /// 있도록 **판정에 필요한 최소 질의만** 클로저로 받는다.
    private let isExecutable: @Sendable (String) -> Bool

    public init(
        cliName: String,
        isExecutable: @escaping @Sendable (String) -> Bool = {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    ) {
        self.cliName = cliName
        self.isExecutable = isExecutable
    }

    public func run() async -> [DoctorFinding] {
        let home = NSHomeDirectory()
        let candidates = [
            HostPlatform.cliBinPath(cliName),
            "/usr/local/bin/\(cliName)",
            (home as NSString).appendingPathComponent(".local/bin/\(cliName)"),
        ]
        guard candidates.first(where: { isExecutable($0) }) == nil else {
            return []
        }
        return [DoctorFinding(
            category: .install,
            severity: .fail,
            body: .init(
                subject: cliName,
                title: "PATH 에 CLI 가 없다",
                detail: "찾은 곳: \(candidates.joined(separator: ", "))",
                remedy: "app-build-manager ship <앱> release"
            ),
            source: id
        )]
    }
}

/// **이 진입 경로에서 리소스 번들이 해석되나.**
///
/// SwiftPM 이 만든 `Bundle.module` 은 `Bundle.main` 자리에서
/// `<Package>_<Target>.bundle` 을 찾고 못 찾으면 **`fatalError` 로 죽는다**(잡을 수 없다).
/// PATH 이름이 심링크면 그 심링크가 놓인 디렉터리를 보므로, 번들이 앱 번들의
/// `Contents/Helpers/` 에만 있으면 **PATH 이름으로 부를 때만 죽는다.**
///
/// 실측(2026-08-11): `product-evaluationctl list` 가 그렇게 죽었다. 실경로로 부르면
/// 멀쩡하고 `ls -l` 로는 정상 심링크라 설치 검사(그림자·낡은 사본·GUI 심링크)가 전부
/// 통과한다. 밖에서 경로만 보는 규칙을 두 번 만들어 봤는데 **둘 다 틀렸다** — 멀쩡한
/// 앱을 신고하고 정작 죽는 앱을 놓쳤다. 진입 경로를 아는 건 그 프로세스뿐이라
/// 검사도 거기 있어야 한다.
public struct ResourceBundleProvider: DoctorProvider {
    public let id = "resource-bundle"
    private let cliName: String
    private let mainBundleURL: URL?
    private let resourceURL: URL?
    private let executableURL: URL?
    private let names: @Sendable (String) -> [String]

    public init(
        cliName: String,
        mainBundleURL: URL? = Bundle.main.bundleURL,
        resourceURL: URL? = Bundle.main.resourceURL,
        executableURL: URL? = Bundle.main.executableURL,
        names: @escaping @Sendable (String) -> [String] = {
            (try? FileManager.default.contentsOfDirectory(atPath: $0)) ?? []
        }
    ) {
        self.cliName = cliName
        self.mainBundleURL = mainBundleURL
        self.resourceURL = resourceURL
        self.executableURL = executableURL
        self.names = names
    }

    public func run() async -> [DoctorFinding] {
        guard let missing = hazard() else { return [] }
        return [DoctorFinding(
            category: .install,
            severity: .fail,
            body: .init(
                subject: cliName,
                title: "이 진입 경로에서 리소스를 못 찾는다",
                detail: "\(missing) 이 실행 파일 실경로 옆에만 있다 — 이 자리로 부르면"
                + " Bundle.module 이 fatalError 로 죽는다",
                remedy: "앱 코드가 실행 파일 실경로 옆을 먼저 보게 하거나, 실경로로 부를 것"
            ),
            source: id
        )]
    }

    func hazard() -> String? {
        func bundles(in directory: URL?) -> Set<String> {
            guard let directory else { return [] }
            return Set(names(directory.path).filter { $0.hasSuffix(".bundle") })
        }
        // 실경로 옆에 리소스 번들이 없으면 이 앱은 리소스를 안 쓴다 — 볼 것도 없다.
        let atReal = bundles(
            in: executableURL?.resolvingSymlinksInPath().deletingLastPathComponent()
        )
        guard !atReal.isEmpty else { return nil }
        let searched = bundles(in: mainBundleURL).union(bundles(in: resourceURL))
        guard searched.isDisjoint(with: atReal) else { return nil }
        return atReal.sorted().first
    }
}

/// 상태 미러를 게시했나. 없다고 앱이 고장난 건 아니라 경고다.
public struct StateMirrorProvider: DoctorProvider {
    public let id = "state-mirror"
    private let appKey: String
    private let directory: String
    private let exists: @Sendable (String) -> Bool

    public init(
        appKey: String,
        directory: String = StateRootKit.path(".swift-app-state"),
        exists: @escaping @Sendable (String) -> Bool = {
            FileManager.default.fileExists(atPath: $0)
        }
    ) {
        self.appKey = appKey
        self.directory = directory
        self.exists = exists
    }

    public func run() async -> [DoctorFinding] {
        let path = (directory as NSString).appendingPathComponent("\(appKey).json")
        guard !exists(path) else { return [] }
        return [DoctorFinding(
            category: .runtime,
            severity: .warn,
            body: .init(
                subject: appKey,
                title: "상태 미러가 없다",
                detail: path,
                remedy: "앱이 상태가 바뀔 때 StateMirror.publish 를 부르는지 확인"
            ),
            source: id
        )]
    }
}
