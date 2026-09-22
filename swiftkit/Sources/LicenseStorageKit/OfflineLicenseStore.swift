import Foundation

/// 오프라인 라이선스 파일 영속화 및 조회 저장소.
public struct OfflineLicenseStore: Sendable {
    public static var defaultDirectory: URL {
        if let custom = ProcessInfo.processInfo.environment["GUJO_OFFLINE_LICENSE_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: ("~/Library/Application Support" as NSString).expandingTildeInPath, isDirectory: true)
        return base.appendingPathComponent("Gujo/licenses", isDirectory: true)
    }

    public let directory: URL
    public let validator: OfflineLicenseValidator

    public init(
        directory: URL? = nil,
        validator: OfflineLicenseValidator = OfflineLicenseValidator()
    ) {
        self.directory = directory ?? Self.defaultDirectory
        self.validator = validator
    }

    /// 파일 URL로부터 라이선스를 검증하고 저장소에 활성화(저장).
    @discardableResult
    public func activate(fileURL: URL, expectedBundleId: String? = nil) throws -> OfflineLicenseFile {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw OfflineLicenseError.fileNotFound(fileURL.path)
        }
        let data = try Data(contentsOf: fileURL)
        return try activate(data: data, expectedBundleId: expectedBundleId)
    }

    /// 바이너리 데이터로부터 라이선스를 검증하고 저장소에 활성화(저장).
    @discardableResult
    public func activate(data: Data, expectedBundleId: String? = nil) throws -> OfflineLicenseFile {
        let license = try validator.validate(data: data, expectedBundleId: expectedBundleId)
        try saveLicense(data: data, bundleId: license.bundleId)
        return license
    }

    /// JSON 문자열로부터 라이선스를 검증하고 저장소에 활성화(저장).
    @discardableResult
    public func activate(jsonString: String, expectedBundleId: String? = nil) throws -> OfflineLicenseFile {
        guard let data = jsonString.data(using: .utf8) else {
            throw OfflineLicenseError.invalidFormat("UTF-8 인코딩 실패")
        }
        return try activate(data: data, expectedBundleId: expectedBundleId)
    }

    /// 특정 bundleId에 대해 유효한 오프라인 라이선스 로드 및 검증.
    public func load(for bundleId: String) -> OfflineLicenseFile? {
        // 1. 환경변수 파일 경로 우선 탐색
        if let envPath = ProcessInfo.processInfo.environment["GUJO_OFFLINE_LICENSE_FILE"],
           !envPath.isEmpty {
            let url = URL(fileURLWithPath: (envPath as NSString).expandingTildeInPath)
            do {
                return try validator.validate(fileURL: url, expectedBundleId: bundleId)
            } catch {
                _ = error // 파일이 없거나 서명 불일치 시 다음 경로 탐색
            }
        }

        // 2. 저장소 디렉터리 (<directory>/<bundleId>.json) 탐색
        let targetURL = directory.appendingPathComponent("\(bundleId).json")
        if FileManager.default.fileExists(atPath: targetURL.path) {
            do {
                return try validator.validate(fileURL: targetURL, expectedBundleId: bundleId)
            } catch {
                _ = error // 다음 경로 탐색
            }
        }

        // 3. 대체 확장자 (<directory>/<bundleId>.license)
        let altURL = directory.appendingPathComponent("\(bundleId).license")
        if FileManager.default.fileExists(atPath: altURL.path) {
            do {
                return try validator.validate(fileURL: altURL, expectedBundleId: bundleId)
            } catch {
                _ = error // 다음 경로 탐색
            }
        }

        // 4. 앱 서포트 직접 경로 (~/Library/Application Support/<bundleId>/license.json)
        let userAppSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        if let userAppSupport {
            let appURL = userAppSupport.appendingPathComponent(bundleId).appendingPathComponent("license.json")
            if FileManager.default.fileExists(atPath: appURL.path) {
                do {
                    return try validator.validate(fileURL: appURL, expectedBundleId: bundleId)
                } catch {
                    _ = error // 탐색 실패
                }
            }
        }

        return nil
    }

    /// 유효한 오프라인 라이선스가 존재하는지 여부.
    public func hasValidLicense(for bundleId: String) -> Bool {
        load(for: bundleId) != nil
    }

    /// 저장소 내의 모든 유효 라이선스 목록.
    public func list() -> [OfflineLicenseFile] {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return []
        }
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        } catch {
            return []
        }
        var result: [OfflineLicenseFile] = []
        for fileURL in files where fileURL.pathExtension == "json" || fileURL.pathExtension == "license" {
            do {
                let lic = try validator.validate(fileURL: fileURL)
                result.append(lic)
            } catch {
                _ = error // 잘못된 서명 또는 형식의 파일은 건너뜀
            }
        }
        return result
    }

    /// 저장소에서 특정 bundleId의 라이선스 삭제.
    public func remove(for bundleId: String) throws {
        let jsonURL = directory.appendingPathComponent("\(bundleId).json")
        if FileManager.default.fileExists(atPath: jsonURL.path) {
            try FileManager.default.removeItem(at: jsonURL)
        }
        let licURL = directory.appendingPathComponent("\(bundleId).license")
        if FileManager.default.fileExists(atPath: licURL.path) {
            try FileManager.default.removeItem(at: licURL)
        }
    }

    private func saveLicense(data: Data, bundleId: String) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directory.path) {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        }
        let targetURL = directory.appendingPathComponent("\(bundleId).json")
        try data.write(to: targetURL, options: .atomic)
    }
}
