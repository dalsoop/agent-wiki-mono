import Foundation

/// CommandKit 자체 호스트 플랫폼 경로 상수.
/// InteropKit으로의 층위 역전을 방지하기 위해 최소 필수 경로를 독립적으로 정의합니다.
public enum HostPlatformPaths {
    /// Homebrew prefix — arm64: `/opt/homebrew`, x86_64: `/usr/local`.
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
}
