import FastDiskIOKit
import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Apple 공증(Notarize) 완료 및 릴리즈 아티팩트(.dmg/.zip/.pkg/.app) 생성 시점에
/// Notary submission ID, SHA-256 체크섬, 파일 크기, 타임스탬프를 취합하여
/// `release-receipt.json`을 원자적으로 생성하고 불변(0o444)으로 봉인하는 서비스.
public struct ReleaseReceiptService: Sendable {
    public init() {}

    public enum ServiceError: LocalizedError, Equatable {
        case fileNotFound(String)
        case cannotReadFile(String)
        case metadataMissing(String)
        case writeFailed(String)

        public var errorDescription: String? {
            switch self {
            case .fileNotFound(let p): return "파일을 찾을 수 없습니다: \(p)"
            case .cannotReadFile(let p): return "파일을 읽을 수 없습니다: \(p)"
            case .metadataMissing(let m): return "필수 메타데이터 누락: \(m)"
            case .writeFailed(let m): return "영수증 저장 실패: \(m)"
            }
        }
    }

    /// 파일(또는 번들 내 실행파일)의 SHA-256 해시를 16진수 소문자(64자리)로 계산한다.
    public static func sha256(of fileURL: URL) throws -> String {
        let path = fileURL.path
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else {
            throw ServiceError.fileNotFound(path)
        }

        let targetURL: URL
        if isDir.boolValue {
            guard let exeURL = findExecutable(inBundle: fileURL) else {
                throw ServiceError.cannotReadFile("번들 내 실행 파일을 찾을 수 없습니다: \(path)")
            }
            targetURL = exeURL
        } else {
            targetURL = fileURL
        }

        let (hash, _) = try ReceiptVerifier.computeSHA256(for: targetURL)
        return hash
    }

    /// 파일 크기를 바이트 단위로 계산한다. 디렉토리 번들이면 내부 파일들의 크기 합계를 반환한다.
    public static func fileSize(of fileURL: URL) throws -> Int64 {
        let fm = FileManager.default
        let path = fileURL.path
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else {
            throw ServiceError.fileNotFound(path)
        }

        guard !isDir.boolValue else {
            return directorySize(at: fileURL, fm: fm)
        }

        let attrs = try fm.attributesOfItem(atPath: path)
        return (attrs[.size] as? Int64) ?? (attrs[.size] as? NSNumber)?.int64Value ?? 0
    }

    private static func directorySize(at fileURL: URL, fm: FileManager) -> Int64 {
        let entries = FastDirectoryScanner.scanEntries(in: fileURL.path, skipping: [])
        return entries.reduce(0) { total, entry in
            entry.isDirectory ? total : total + entry.size
        }
    }

    /// 파일 확장자에 따른 Content-Type을 추론한다.
    public static func determineContentType(for fileURL: URL) -> String {
        let ext = fileURL.pathExtension.lowercased()
        switch ext {
        case "dmg":
            return "application/x-apple-diskimage"
        case "zip":
            return "application/zip"
        case "pkg":
            return "application/vnd.apple.installer+xml"
        case "app":
            return "application/x-apple-application"
        default:
            return "application/octet-stream"
        }
    }

    /// Info.plist 파일을 안전하게 파싱한다.
    public static func readInfoPlist(at plistURL: URL) -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: plistURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: plistURL)
            return try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        } catch {
            _ = error
            return nil
        }
    }

    /// 번들 디렉토리 내의 메인 실행파일을 찾는다.
    private static func findExecutable(inBundle bundleURL: URL) -> URL? {
        let infoPlistURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        if let plist = readInfoPlist(at: infoPlistURL),
           let exeName = plist["CFBundleExecutable"] as? String {
            let exeURL = bundleURL.appendingPathComponent("Contents/MacOS").appendingPathComponent(exeName)
            if FileManager.default.fileExists(atPath: exeURL.path) {
                return exeURL
            }
        }
        let macosDir = bundleURL.appendingPathComponent("Contents/MacOS")
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: macosDir, includingPropertiesForKeys: nil)
            return contents.first
        } catch {
            _ = error
            return nil
        }
    }

    /// `release-receipt.json`을 원자적으로 기록하고 불변(0o444)으로 봉인한다.
    public static func writeAtomicAndSeal(
        receipt: ReleaseReceipt,
        destinationDirectory: URL,
        fileName: String = "release-receipt.json",
        makeImmutable: Bool = true
    ) throws -> URL {
        let fm = FileManager.default
        if !fm.fileExists(atPath: destinationDirectory.path) {
            try fm.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        }

        let targetURL = destinationDirectory.appendingPathComponent(fileName)
        let tempURL = destinationDirectory.appendingPathComponent(".\(fileName).tmp.\(UUID().uuidString)")

        let data = try receipt.toJSONData()
        try data.write(to: tempURL, options: .atomic)

        if fm.fileExists(atPath: targetURL.path) {
            do {
                try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: targetURL.path)
            } catch {
                _ = error
            }
            _ = try fm.replaceItemAt(targetURL, withItemAt: tempURL)
        } else {
            if fm.fileExists(atPath: targetURL.path) {
                try fm.removeItem(at: targetURL)
            }
            try fm.moveItem(at: tempURL, to: targetURL)
        }

        if makeImmutable {
            try fm.setAttributes([.posixPermissions: 0o444], ofItemAtPath: targetURL.path)
        }

        return targetURL
    }

    public struct SealReceiptOptions: Sendable {
        public let artifactURL: URL
        public let submissionID: String
        public let notarizedAt: Date
        public let teamID: String?
        public let appSlug: String
        public let bundleID: String
        public let version: String
        public let buildNumber: Int?
        public let sparkleSignature: String?
        public let destinationDirectory: URL
        public let fileName: String
        public let makeImmutable: Bool

        public init(
            artifactURL: URL,
            submissionID: String,
            notarizedAt: Date = Date(),
            teamID: String? = nil,
            appSlug: String,
            bundleID: String,
            version: String,
            buildNumber: Int? = nil,
            sparkleSignature: String? = nil,
            destinationDirectory: URL,
            fileName: String = "release-receipt.json",
            makeImmutable: Bool = true
        ) {
            self.artifactURL = artifactURL
            self.submissionID = submissionID
            self.notarizedAt = notarizedAt
            self.teamID = teamID
            self.appSlug = appSlug
            self.bundleID = bundleID
            self.version = version
            self.buildNumber = buildNumber
            self.sparkleSignature = sparkleSignature
            self.destinationDirectory = destinationDirectory
            self.fileName = fileName
            self.makeImmutable = makeImmutable
        }
    }

    /// 공증 완료된 아티팩트의 해시와 메타데이터를 수집하여 영수증을 빌드하고 봉인한다.
    @discardableResult
    public static func sealReceipt(options: SealReceiptOptions) throws -> ReleaseReceipt {
        let sha = try sha256(of: options.artifactURL)
        let size = try fileSize(of: options.artifactURL)
        let contentType = determineContentType(for: options.artifactURL)

        var builder = ReceiptBuilder()
            .setAppSlug(options.appSlug)
            .setBundleID(options.bundleID)
            .setVersion(options.version)
            .setArtifact(
                filename: options.artifactURL.lastPathComponent,
                sha256: sha,
                sizeBytes: size,
                contentType: contentType
            )
            .setNotary(
                submissionID: options.submissionID,
                notarizedAt: options.notarizedAt,
                teamID: options.teamID
            )

        if let bn = options.buildNumber {
            builder = builder.setBuildNumber(bn)
        }
        if let sig = options.sparkleSignature {
            builder = builder.setSparkle(ed25519Signature: sig)
        }

        let receipt = try builder.build()
        _ = try writeAtomicAndSeal(
            receipt: receipt,
            destinationDirectory: options.destinationDirectory,
            fileName: options.fileName,
            makeImmutable: options.makeImmutable
        )
        return receipt
    }



    public struct SealAppOptions: Sendable {
        public let appDir: URL?
        public let bundleURL: URL?
        public let artifactURL: URL
        public let submissionID: String
        public let teamID: String?
        public let sparkleSignature: String?
        public let destinationDirectories: [URL]
        public let fileName: String
        public let makeImmutable: Bool

        public init(
            appDir: URL?,
            bundleURL: URL?,
            artifactURL: URL,
            submissionID: String,
            teamID: String? = nil,
            sparkleSignature: String? = nil,
            destinationDirectories: [URL],
            fileName: String = "release-receipt.json",
            makeImmutable: Bool = true
        ) {
            self.appDir = appDir
            self.bundleURL = bundleURL
            self.artifactURL = artifactURL
            self.submissionID = submissionID
            self.teamID = teamID
            self.sparkleSignature = sparkleSignature
            self.destinationDirectories = destinationDirectories
            self.fileName = fileName
            self.makeImmutable = makeImmutable
        }
    }

    /// 앱 디렉토리와 번들을 분석하여 메타데이터를 자동 추출하고 영수증을 봉인한다.
    @discardableResult
    public static func sealReceiptForApp(options: SealAppOptions) throws -> ReleaseReceipt {
        var bundleID: String?
        var version: String?
        var buildNumber: Int?

        if let bundleURL = options.bundleURL,
           let plist = readInfoPlist(at: bundleURL.appendingPathComponent("Contents/Info.plist")) {
            bundleID = plist["CFBundleIdentifier"] as? String
            version = plist["CFBundleShortVersionString"] as? String
            if let buildStr = plist["CFBundleVersion"] as? String {
                buildNumber = Int(buildStr)
            }
        }

        if let appDir = options.appDir, bundleID == nil || version == nil,
           let plist = readInfoPlist(at: appDir.appendingPathComponent("Packaging/Info.plist")) {
            if bundleID == nil { bundleID = plist["CFBundleIdentifier"] as? String }
            if version == nil { version = plist["CFBundleShortVersionString"] as? String }
            if buildNumber == nil, let buildStr = plist["CFBundleVersion"] as? String {
                buildNumber = Int(buildStr)
            }
        }

        let appSlug = resolveSlug(appDir: options.appDir, artifactURL: options.artifactURL)
        guard let finalBundleID = bundleID ?? plistBundleID(from: options.artifactURL) else {
            throw ServiceError.metadataMissing("bundleID를 확인할 수 없습니다.")
        }
        guard let finalVersion = version ?? plistVersion(from: options.artifactURL) else {
            throw ServiceError.metadataMissing("version을 확인할 수 없습니다.")
        }

        let primaryDest = options.destinationDirectories.first ?? options.artifactURL.deletingLastPathComponent()
        let receipt = try sealReceipt(options: SealReceiptOptions(
            artifactURL: options.artifactURL,
            submissionID: options.submissionID,
            notarizedAt: Date(),
            teamID: options.teamID,
            appSlug: appSlug,
            bundleID: finalBundleID,
            version: finalVersion,
            buildNumber: buildNumber,
            sparkleSignature: options.sparkleSignature,
            destinationDirectory: primaryDest,
            fileName: options.fileName,
            makeImmutable: options.makeImmutable
        ))

        for extraDest in options.destinationDirectories.dropFirst() {
            _ = try writeAtomicAndSeal(
                receipt: receipt,
                destinationDirectory: extraDest,
                fileName: options.fileName,
                makeImmutable: options.makeImmutable
            )
        }

        return receipt
    }

    private static func resolveSlug(appDir: URL?, artifactURL: URL) -> String {
        if let appDir {
            var s = appDir.lastPathComponent
            if s.hasPrefix("apps/") { s = String(s.dropFirst(5)) }
            for suffix in ["-swift", "-ios", "-macos"] where s.hasSuffix(suffix) {
                s = String(s.dropLast(suffix.count))
                break
            }
            return s
        }
        var s = artifactURL.deletingPathExtension().lastPathComponent
        if let idx = s.firstIndex(of: "-") { s = String(s[..<idx]) }
        return s
    }

    private static func plistBundleID(from url: URL) -> String? {
        readInfoPlist(at: url.appendingPathComponent("Contents/Info.plist"))?["CFBundleIdentifier"] as? String
    }

    private static func plistVersion(from url: URL) -> String? {
        readInfoPlist(at: url.appendingPathComponent("Contents/Info.plist"))?["CFBundleShortVersionString"] as? String
    }
}
