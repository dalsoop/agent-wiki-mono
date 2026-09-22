#if canImport(CryptoKit)
import CryptoKit
import Foundation
import CommandKit

/// GitHub release 자산 다운로드. `repo` 는 "owner/name" 형식.
/// mac-ai-installer 원본에서 repo 를 파라미터로 일반화했다.
public protocol ReleaseAssetDownloading: Sendable {
    func download(repo: String, asset: String, to destination: URL, timeoutSeconds: TimeInterval) async -> CommandResult
}

public struct URLSessionReleaseAssetDownloader: ReleaseAssetDownloading {
    public init() {}

    public func download(repo: String, asset: String, to destination: URL, timeoutSeconds: TimeInterval) async -> CommandResult {
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let release = try await latestRelease(repo: repo, timeoutSeconds: timeoutSeconds)
            guard let assetInfo = release.assets.first(where: { $0.name == asset }) else {
                return CommandResult(stdout: "", stderr: "Release asset not found: \(asset)", exitCode: 1)
            }
            var request = URLRequest(url: assetInfo.browserDownloadURL)
            request.timeoutInterval = timeoutSeconds
            let (tempURL, response) = try await URLSession.shared.download(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return CommandResult(stdout: "", stderr: "Asset download failed: \(asset)", exitCode: 1)
            }
            let dest = destination.appendingPathComponent(asset)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: tempURL, to: dest)
            // Verify against the release's SHA256SUMS before the binary is ever chmod+x'd / executed.
            // Fail-closed: a missing SHA256SUMS, missing entry, or mismatch aborts and deletes the file.
            let sumsURL = release.assets.first(where: { $0.name == "SHA256SUMS" })?.browserDownloadURL
            if let failure = await Self.verifyChecksum(asset: asset, file: dest, sumsURL: sumsURL, timeoutSeconds: timeoutSeconds) {
                try? FileManager.default.removeItem(at: dest)
                return CommandResult(stdout: "", stderr: failure, exitCode: 1)
            }
            return CommandResult(stdout: "Downloaded+verified \(asset) from \(release.tagName) (repo \(repo)).", stderr: "", exitCode: 0)
        } catch {
            return CommandResult(stdout: "", stderr: error.localizedDescription, exitCode: 1)
        }
    }

    /// nil = checksum verified. Non-nil = failure message. Fail-closed by design — the user opted into
    /// SHA256SUMS verification, so anything we can't positively verify aborts the install.
    static func verifyChecksum(asset: String, file: URL, sumsURL: URL?, timeoutSeconds: TimeInterval) async -> String? {
        guard let sumsURL else {
            return "릴리스에 SHA256SUMS 없음 — 검증 불가로 설치 중단(릴리스에 SHA256SUMS 게시 필요)"
        }
        var request = URLRequest(url: sumsURL)
        request.timeoutInterval = timeoutSeconds
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let text = String(data: data, encoding: .utf8) else {
            return "SHA256SUMS 다운로드 실패 — 검증 불가로 설치 중단"
        }
        guard let expected = parseExpectedHash(from: text, asset: asset) else {
            return "SHA256SUMS 에 \(asset) 항목 없음 — 검증 실패"
        }
        guard let fileData = try? Data(contentsOf: file) else { return "다운로드 파일 읽기 실패" }
        guard sha256Hex(of: fileData) == expected else {
            return "체크섬 불일치 (\(asset)) — 손상/위변조 가능, 설치 중단"
        }
        return nil
    }

    /// Parse `<sha256>␣␣<filename>` lines (coreutils format; filename may have a leading `*`).
    static func parseExpectedHash(from sumsText: String, asset: String) -> String? {
        for line in sumsText.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2 else { continue }
            let name = parts[parts.count - 1].trimmingCharacters(in: CharacterSet(charactersIn: "*"))
            if name == asset { return parts[0].lowercased() }
        }
        return nil
    }

    static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func latestRelease(repo: String, timeoutSeconds: TimeInterval) async throws -> GitHubRelease {
        let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("InstallerKit", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = timeoutSeconds
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let assets: [GitHubAsset]
    private enum CodingKeys: String, CodingKey { case tagName = "tag_name"; case assets }
}

private struct GitHubAsset: Decodable {
    let name: String
    let browserDownloadURL: URL
    private enum CodingKeys: String, CodingKey { case name; case browserDownloadURL = "browser_download_url" }
}
#endif
