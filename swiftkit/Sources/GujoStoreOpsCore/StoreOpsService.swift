import Foundation
import LocalizationKit
import ReleaseReceiptKit
@_exported import GujoStoreBillingKit
@_exported import GujoStoreCatalogKit

/// Mac/iOS 공통 서비스 파사드. adb 설치는 macOS only.
public struct StoreOpsService: Sendable {
    public let client: StoreOpsClient

    public init(client: StoreOpsClient = OpsPreferences.makeClient()) {
        self.client = client
    }

    public func statusLine() async -> String {
        do {
            let h = try await client.health()
            let pkgs = try await client.listPackages()
            var adbNote = "adb n/a"
            #if os(macOS)
            let adb = AdbClient()
            if await adb.isAvailable() {
                let n = await adb.devices().filter(\.isReady).count
                adbNote = CLILocalization.format("StoreOpsService.string", "\(n)")
            } else {
                adbNote = "adb 없음"
            }
            #endif
            let bridge = h.catalogBridge ?? "-"
            let pub = h.catalogPublish ?? "-"
            let auth = h.opsAuth ?? "-"
            let tokenNote: String
            if auth == "required", OpsPreferences.bearerToken == nil {
                tokenNote = "token MISSING"
            } else if auth == "required" {
                tokenNote = "token ok"
            } else {
                tokenNote = "auth \(auth)"
            }
            let runners = h.runnersOnline.map { "runners \($0)" } ?? "runners ?"
            return "\(h.service) · \(pkgs.count) pkg · bridge \(bridge) · publish \(pub) · \(tokenNote) · \(runners) · \(adbNote)"
        } catch {
            return "error: \(error.localizedDescription)"
        }
    }

    public func downloadAPK(from url: URL) async throws -> URL {
        let fetch = CatalogArtifactURL.downloadURL(from: url)
        let (data, resp) = try await URLSession.shared.data(from: fetch)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw StoreOpsError.http(code) }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("gso-\(UUID().uuidString).apk")
        try data.write(to: tmp)
        return tmp
    }

    #if os(macOS)
    public func installPackage(_ pkg: OpsPackage, serial: String?) async throws {
        guard let apkURL = pkg.artifactURL ?? pkg.installURL else {
            throw StoreOpsError.network("no apk url")
        }
        let local = try await downloadAPK(from: apkURL)
        defer { try? FileManager.default.removeItem(at: local) }
        let adb = AdbClient()
        let diag = await adb.diagnose()
        let devices = diag.devices.filter(\.isReady)
        guard !devices.isEmpty else {
            throw StoreOpsError.network("no adb device — \(diag.title). \(diag.summary)")
        }
        try await adb.install(apkPath: local.path, serial: serial ?? devices[0].serial)
    }

    /// 서버 job 을 claim → adb install → report.
    public func runInstallJob(_ job: InstallJob) async throws -> InstallJob {
        let job = try await client.claimInstallJob(id: job.id)
        _ = try await client.reportInstallJob(id: job.id, status: .running, logTail: "downloading")
        let packages = try await client.listPackages()
        guard let pkg = packages.first(where: { $0.packageName == job.packageName }) else {
            return try await client.reportInstallJob(
                id: job.id, status: .failed, error: "package not found", logTail: nil)
        }
        let devices = try await client.listDevices()
        let device = devices.first(where: { $0.id == job.deviceId })
        let serial = device?.serial
        do {
            try await installPackage(pkg, serial: serial)
            return try await client.reportInstallJob(
                id: job.id, status: .succeeded, logTail: "adb install ok")
        } catch {
            return try await client.reportInstallJob(
                id: job.id, status: .failed, error: error.localizedDescription, logTail: nil)
        }
    }
    #endif

    // MARK: - Receipt Ingest

    /// release-receipt.json 파일을 검증하고 스토어로 인제스트한다.
    public func ingestReceipt(
        at fileURL: URL,
        overrideDownloadURL: URL? = nil
    ) async throws -> ReceiptIngestResult {
        let service = ReceiptIngestService()
        return try await service.ingest(
            at: fileURL,
            overrideDownloadURL: overrideDownloadURL,
            client: client
        )
    }

    /// release-receipt.json 파일의 유효성(SHA-256, 파일 크기, Notary ID 등)을 로컬에서 검증한다.
    public func validateReceipt(at fileURL: URL) throws -> ReleaseReceipt {
        let service = ReceiptIngestService()
        return try service.validateReceipt(at: fileURL)
    }
}
