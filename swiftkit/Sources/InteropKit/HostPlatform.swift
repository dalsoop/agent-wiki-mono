import Foundation
import PackageIdentityKit

/// macOS 호스트 아키텍처에 따른 경로 SSOT.
/// `/opt/homebrew` 를 직접 쓰지 말고 이 타입을 참조한다.
public enum HostPlatform {
    /// Homebrew prefix — arm64: `/opt/homebrew`, x86_64: `/usr/local`.
    /// Nix/MacPorts 등 다른 패키지 매니저 경로는 커버하지 않는다.
    /// `/usr/local`은 Homebrew 전용이 아니지만 x86_64 Homebrew 관례 경로다.
    public static var homebrewPrefix: String {
        #if os(macOS)
        #if arch(arm64)
        "/opt/homebrew"
        #else
        "/usr/local"
        #endif
        #else
        "/usr/local"
        #endif
    }

    /// Homebrew bin directory.
    public static var homebrewBin: String { "\(homebrewPrefix)/bin" }

    /// CLI 실행파일 탐색 표준 경로 (우선순위 순, 중복 제거).
    public static var standardBinPaths: [String] {
        var paths = [homebrewBin]
        if homebrewBin != "/usr/local/bin" { paths.append("/usr/local/bin") }
        paths.append("\(NSHomeDirectory())/.local/bin")
        return paths
    }

    /// PATH 환경변수 앞에 붙일 표준 경로.
    public static var pathPrefix: String {
        standardBinPaths.joined(separator: ":")
    }

    /// 주어진 CLI 이름의 표준 설치 경로.
    public static func cliBinPath(_ name: String) -> String {
        "\(homebrewBin)/\(name)"
    }

    /// Homebrew · `/usr/local/bin` · `~/.local/bin` 후보 (중복 제거된 `standardBinPaths` 위).
    public static func binCandidates(forCLI name: String) -> [String] {
        standardBinPaths.map { "\($0)/\(name)" }
    }

    /// prefix+object 공식 CLI 이름. `app` 접두는 붙이지 않는다.
    public static func liveCLIName(prefix: String, objectNoun: String) -> String {
        IdentityFormula.liveCLIName(prefix: prefix, objectNoun: objectNoun)
    }

    public static func liveCLIName(_ identity: AppIdentity) -> String {
        IdentityFormula.liveCLIName(
            prefix: identity.prefix ?? "",
            objectNoun: identity.object ?? "")
    }

    /// 이 프로세스 실행 파일의 카드에서 민트. 카드가 없으면 argv0 파일명.
    public static func liveCLIName(
        executablePath: String = ProcessInfo.processInfo.arguments.first ?? CommandLine.arguments[0]
    ) -> String {
        let url = URL(fileURLWithPath: executablePath)
        if let identity = AppIdentityLocator.locate(executable: url) {
            let minted = liveCLIName(identity)
            if !minted.isEmpty { return minted }
            if let cli = identity.cli, !cli.isEmpty { return cli }
        }
        return url.lastPathComponent
    }

    public static func liveCLIPath(prefix: String, objectNoun: String) -> String {
        cliBinPath(liveCLIName(prefix: prefix, objectNoun: objectNoun))
    }

    public static func liveCLIPath(
        executablePath: String = ProcessInfo.processInfo.arguments.first ?? CommandLine.arguments[0]
    ) -> String {
        cliBinPath(liveCLIName(executablePath: executablePath))
    }

    /// ProcessInfo 호스트 이름. scutil 은 호출측 hang 워치독이 InteropKit 에서
    /// CommandKit.ProcessWait 를 끌어올 수 없어 쓰지 않는다.
    public static var localHostName: String {
        ProcessInfo.processInfo.hostName
    }

    /// 3-Tier 빌드 클러스터 내 호스트 머신 역할.
    public enum ClusterHostRole: String, Codable, Sendable, Equatable {
        case thisMac = "This-Mac (Local Builder)"
        case nextMac = "Next-Mac (Workstation Worker)"
        case unknown = "Unknown"

        public var role: String {
            switch self {
            case .thisMac: return "Local Builder"
            case .nextMac: return "Workstation Worker"
            case .unknown: return "Unknown"
            }
        }

        public var remotePeer: ClusterHostRole {
            switch self {
            case .thisMac: return .nextMac
            case .nextMac: return .thisMac
            case .unknown: return .unknown
            }
        }
    }

    /// 호스트 이름으로부터 클러스터 머신 역할 판정.
    /// - "jeonghanui-MacBookPro" (또는 "ui" 포함): This-Mac (Local Builder)
    /// - "jeonghans-MacBook-Pro" (또는 "hans" 포함): Next-Mac (Workstation Worker)
    public static func clusterHostRole(for hostName: String = localHostName) -> ClusterHostRole {
        let lower = hostName.lowercased()
        let hasUiToken = lower.contains("ui") && !lower.contains("build")
        let isThisMac = lower == "jeonghanui-macbookpro"
            || lower.contains("jeonghanui")
            || lower.contains("-ui")
            || lower.contains("ui-")
            || hasUiToken
        if isThisMac { return .thisMac }
        let isNextMac = lower == "jeonghans-macbook-pro"
            || lower.contains("jeonghans")
            || lower.contains("hans")
        if isNextMac { return .nextMac }
        return .unknown
    }
}
