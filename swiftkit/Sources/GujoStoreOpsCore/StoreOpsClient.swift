import Foundation

/// Gujo Store Ops API 클라이언트.
///
/// - **auto**: ops health 성공 시 opsAPI, 아니면 catalog-v1 브릿지
/// - **catalogV1Bridge**: catalog index.json
/// - **opsAPI**: software `/api/ops/v1/*`
public struct StoreOpsClient: Sendable {
    public enum Mode: Sendable, Equatable {
        case auto
        case catalogV1Bridge
        case opsAPI
    }

    public var mode: Mode
    public var catalogBaseURL: URL
    public var opsBaseURL: URL
    public var session: URLSession
    public var bearerToken: String?
    public var tokenProvider: any StaffTokenProviding
    public var staffHTTP: any StaffHTTPTransport

    public static let defaultCatalogURL = CatalogV1Bridge.defaultBaseURL
    /// EndpointRouterKit 키 (`OpsPreferences`).
    public static var defaultOpsURL: URL { OpsPreferences.baseURL }

    public init(
        mode: Mode = .auto,
        catalogBaseURL: URL = StoreOpsClient.defaultCatalogURL,
        opsBaseURL: URL = StoreOpsClient.defaultOpsURL,
        session: URLSession = .shared,
        bearerToken: String? = nil,
        tokenProvider: (any StaffTokenProviding)? = nil,
        staffHTTP: (any StaffHTTPTransport)? = nil
    ) {
        self.mode = mode
        self.catalogBaseURL = catalogBaseURL
        self.opsBaseURL = opsBaseURL
        self.session = session
        self.tokenProvider = tokenProvider ?? OpsPreferences.tokenProvider
        self.staffHTTP = staffHTTP ?? URLSessionStaffHTTP(session: session)
        self.bearerToken = bearerToken
    }

    public func resolvedStaffToken() -> String? {
        if let bearerToken, !bearerToken.isEmpty { return bearerToken }
        return try? tokenProvider.staffToken()
    }

    public func publishSkill(_ request: SkillMutationRequest) async throws -> SkillMutationResult {
        try await SkillStaffClient(
            baseURL: opsBaseURL,
            tokenProvider: StaticStaffTokenProvider(token: resolvedStaffToken()),
            http: staffHTTP
        ).publish(request)
    }

    public func deprecateSkill(_ request: SkillMutationRequest) async throws -> SkillMutationResult {
        try await SkillStaffClient(
            baseURL: opsBaseURL,
            tokenProvider: StaticStaffTokenProvider(token: resolvedStaffToken()),
            http: staffHTTP
        ).deprecate(request)
    }

    public func auditDownloadPipeline() async throws -> DownloadPipelineAudit {
        try await DownloadPipelineStaffClient(
            baseURL: opsBaseURL,
            tokenProvider: StaticStaffTokenProvider(token: resolvedStaffToken()),
            http: staffHTTP
        ).audit()
    }

    // MARK: - Resolve mode

    private func resolvedMode() async -> Mode {
        if mode != .auto { return mode }
        do {
            let url = opsBaseURL.appendingPathComponent("api/ops/v1/health")
            _ = try await get(url)
            return .opsAPI
        } catch {
            return .catalogV1Bridge
        }
    }

    // MARK: - Health

    public func health() async throws -> OpsHealth {
        switch await resolvedMode() {
        case .catalogV1Bridge, .auto:
            let ok = await catalogHealthz()
            return OpsHealth(ok: ok, service: "catalog-v1-bridge", catalogBridge: ok ? "up" : "down")
        case .opsAPI:
            let url = opsBaseURL.appendingPathComponent("api/ops/v1/health")
            let data = try await get(url)
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw StoreOpsError.decode("health")
            }
            return OpsHealth(
                ok: obj["ok"] as? Bool ?? false,
                service: obj["service"] as? String ?? "gujo-software-ops",
                catalogBridge: obj["catalog_bridge"] as? String,
                catalogPublish: obj["catalog_publish"] as? String,
                opsAuth: obj["ops_auth"] as? String,
                runnersOnline: obj["runners_online"] as? Int
            )
        }
    }

    // MARK: - Packages

    public func listPackages() async throws -> [OpsPackage] {
        switch await resolvedMode() {
        case .catalogV1Bridge, .auto:
            let url = catalogBaseURL.appendingPathComponent("index.json")
            let data = try await get(url)
            return try CatalogV1Bridge.parseIndex(data, baseURL: catalogBaseURL)
        case .opsAPI:
            let url = opsBaseURL.appendingPathComponent("api/ops/v1/packages")
            let data = try await get(url)
            return try decodePackages(data)
        }
    }

    // MARK: - Devices

    public func listDevices() async throws -> [OpsDevice] {
        guard await resolvedMode() == .opsAPI else {
            throw StoreOpsError.notImplemented("devices require opsAPI")
        }
        let url = opsBaseURL.appendingPathComponent("api/ops/v1/devices")
        let data = try await get(url)
        return try decodeDevices(data)
    }

    public func createDevice(label: String, serial: String?, state: String = "ready") async throws -> OpsDevice {
        guard await resolvedMode() == .opsAPI else {
            throw StoreOpsError.notImplemented("devices require opsAPI")
        }
        let url = opsBaseURL.appendingPathComponent("api/ops/v1/devices")
        var body: [String: String] = ["label": label, "state": state, "platform": "android"]
        if let serial { body["serial"] = serial }
        let data = try await post(url, json: body)
        return try decodeDevice(data)
    }

    // MARK: - Install jobs

    public func listInstallJobs(status: InstallJobStatus? = nil) async throws -> [InstallJob] {
        guard await resolvedMode() == .opsAPI else {
            throw StoreOpsError.notImplemented("jobs require opsAPI")
        }
        var url = opsBaseURL.appendingPathComponent("api/ops/v1/install-jobs")
        if let status {
            var c = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            c.queryItems = [URLQueryItem(name: "status", value: status.rawValue)]
            url = c.url ?? url
        }
        let data = try await get(url)
        return try decodeJobs(data)
    }

    public func createInstallJob(packageName: String, deviceId: String) async throws -> InstallJob {
        guard await resolvedMode() == .opsAPI else {
            throw StoreOpsError.notImplemented("jobs require opsAPI")
        }
        let url = opsBaseURL.appendingPathComponent("api/ops/v1/install-jobs")
        let data = try await post(url, json: [
            "package_name": packageName,
            "device_id": deviceId,
        ])
        return try decodeJobEnvelope(data)
    }

    public func claimInstallJob(id: String) async throws -> InstallJob {
        let url = opsBaseURL.appendingPathComponent("api/ops/v1/install-jobs/\(id)/claim")
        let data = try await post(url, json: [:])
        return try decodeJobEnvelope(data)
    }

    public func reportInstallJob(
        id: String,
        status: InstallJobStatus,
        error: String? = nil,
        logTail: String? = nil
    ) async throws -> InstallJob {
        let url = opsBaseURL.appendingPathComponent("api/ops/v1/install-jobs/\(id)/report")
        var body: [String: String] = ["status": status.rawValue]
        if let error { body["error"] = error }
        if let logTail { body["log_tail"] = logTail }
        let data = try await post(url, json: body)
        return try decodeJobEnvelope(data)
    }

    public func cancelInstallJob(id: String) async throws -> InstallJob {
        guard await resolvedMode() == .opsAPI else {
            throw StoreOpsError.notImplemented("cancel requires opsAPI")
        }
        let url = opsBaseURL.appendingPathComponent("api/ops/v1/install-jobs/\(id)/cancel")
        let data = try await post(url, json: [:])
        return try decodeJobEnvelope(data)
    }

    // MARK: - Publish + audit

    /// catalog 실발행. `apkURL`(로컬 파일) 또는 `artifactURL`(원격) 중 하나 필수.
    public func publishPackage(
        _ packageName: String,
        apkURL: URL? = nil,
        artifactURL: URL? = nil,
        name: String? = nil,
        summary: String? = nil
    ) async throws -> String {
        guard await resolvedMode() == .opsAPI else {
            throw StoreOpsError.notImplemented("publish requires opsAPI")
        }
        let path = "api/ops/v1/packages/\(packageName)/publish"
        let url = opsBaseURL.appendingPathComponent(path)

        let data: Data
        if let apkURL {
            data = try await postMultipartAPK(
                url,
                apkURL: apkURL,
                fields: [
                    "name": name,
                    "summary": summary,
                ]
            )
        } else if let artifactURL {
            var body: [String: String] = ["artifact_url": artifactURL.absoluteString]
            if let name { body["name"] = name }
            if let summary { body["summary"] = summary }
            data = try await post(url, json: body)
        } else {
            let pkg: OpsPackage?
            do {
                pkg = try await listPackages().first(where: { $0.packageName == packageName })
            } catch {
                pkg = nil
            }
            if let pkg, let existing = pkg.artifactURL {
                // 기존 아티팩트 재발행 (서버가 받아 catalog 로 프록시)
                data = try await post(url, json: [
                    "artifact_url": existing.absoluteString,
                    "name": name ?? pkg.displayName,
                ])
            } else {
                throw StoreOpsError.notImplemented("apk path or artifact_url required for real publish")
            }
        }

        if let obj = StoreOpsJSON.object(from: data) {
            if let ok = obj["ok"] as? Bool, ok == false {
                let msg = (obj["error"] as? [String: Any])?["message"] as? String
                    ?? "publish failed"
                throw StoreOpsError.network(msg)
            }
            let status = obj["status"] as? String
            let message = obj["message"] as? String
            if let vn = (obj["result"] as? [String: Any])?["versionName"] as? String {
                return "\(message ?? status ?? "published") · v\(vn)"
            }
            return message ?? status ?? "published"
        }
        return "published"
    }

    // MARK: - Receipt Ingest

    /// release-receipt.json 증거를 스토어로 인제스트하여 릴리스를 등록하고 판매 가능 상태로 전이한다.
    public func ingestReceipt(
        receiptData: Data,
        overrideDownloadURL: URL? = nil
    ) async throws -> ReceiptIngestResult {
        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: receiptData)
        } catch {
            throw StoreOpsError.decode("receipt data is not valid json: \(error.localizedDescription)")
        }
        var json = (jsonObject as? [String: Any]) ?? [:]
        if let overrideDownloadURL {
            json["override_download_url"] = overrideDownloadURL.absoluteString
        }

        let url = opsBaseURL.appendingPathComponent("api/ops/v1/receipts/ingest")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(&req)
        req.httpBody = try JSONSerialization.data(withJSONObject: json)

        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let errorMsg: String
            do {
                let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let err = obj?["error"] as? [String: Any]
                errorMsg = err?["message"] as? String ?? "HTTP \(code)"
            } catch {
                throw StoreOpsError.http(code)
            }
            throw StoreOpsError.network("HTTP \(code): \(errorMsg)")
        }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var resultObj = root["result"] as? [String: Any] else {
            throw StoreOpsError.decode("receipt ingest response")
        }
        if resultObj["ok"] == nil {
            resultObj["ok"] = root["ok"] ?? true
        }
        let resultData = try JSONSerialization.data(withJSONObject: resultObj)
        return try JSONDecoder().decode(ReceiptIngestResult.self, from: resultData)
    }

    public func listRunners() async throws -> [OpsRunner] {
        guard await resolvedMode() == .opsAPI else {
            throw StoreOpsError.notImplemented("runners require opsAPI")
        }
        let url = opsBaseURL.appendingPathComponent("api/ops/v1/runners")
        let data = try await get(url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = root["runners"] as? [[String: Any]] else {
            throw StoreOpsError.decode("runners")
        }
        return arr.compactMap { obj in
            guard let id = obj["id"] as? String, let host = obj["host"] as? String else { return nil }
            return OpsRunner(
                id: id,
                host: host,
                label: obj["label"] as? String,
                status: obj["status"] as? String ?? "offline",
                online: obj["online"] as? Bool ?? false,
                adbReadyCount: obj["adb_ready_count"] as? Int ?? 0,
                lastSeenAt: obj["last_seen_at"] as? String
            )
        }
    }

    public func runnerHeartbeat(
        host: String,
        label: String? = nil,
        adbReadyCount: Int = 0,
        status: String = "online"
    ) async throws -> OpsRunner {
        guard await resolvedMode() == .opsAPI else {
            throw StoreOpsError.notImplemented("runners require opsAPI")
        }
        let url = opsBaseURL.appendingPathComponent("api/ops/v1/runners/heartbeat")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(&req)
        var json: [String: Any] = [
            "host": host,
            "status": status,
            "adb_ready_count": adbReadyCount,
        ]
        if let label { json["label"] = label }
        req.httpBody = try JSONSerialization.data(withJSONObject: json)
        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw StoreOpsError.http(code) }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let obj = root["runner"] as? [String: Any],
              let id = obj["id"] as? String,
              let h = obj["host"] as? String else {
            throw StoreOpsError.decode("runner")
        }
        return OpsRunner(
            id: id,
            host: h,
            label: obj["label"] as? String,
            status: obj["status"] as? String ?? status,
            online: obj["online"] as? Bool ?? true,
            adbReadyCount: obj["adb_ready_count"] as? Int ?? adbReadyCount,
            lastSeenAt: obj["last_seen_at"] as? String
        )
    }

    public func listAudit(limit: Int = 50) async throws -> [OpsAuditEvent] {
        guard await resolvedMode() == .opsAPI else {
            throw StoreOpsError.notImplemented("audit requires opsAPI")
        }
        var c = URLComponents(
            url: opsBaseURL.appendingPathComponent("api/ops/v1/audit"),
            resolvingAgainstBaseURL: false
        )!
        c.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        let data = try await get(c.url!)
        return try decodeAudit(data)
    }

    // MARK: - HTTP

    private func catalogHealthz() async -> Bool {
        let url = catalogBaseURL.appendingPathComponent("healthz")
        do {
            let (_, resp) = try await session.data(from: url)
            return ((resp as? HTTPURLResponse)?.statusCode ?? 0) == 200
        } catch {
            return false
        }
    }

    private func get(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        applyAuth(&req)
        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw StoreOpsError.http(code) }
        return data
    }

    private func post(_ url: URL, json: [String: String]) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(&req)
        req.httpBody = try JSONSerialization.data(withJSONObject: json)
        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw StoreOpsError.http(code) }
        return data
    }

    private func postMultipartAPK(
        _ url: URL,
        apkURL: URL,
        fields: [String: String?]
    ) async throws -> Data {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        for (key, value) in fields {
            guard let value, !value.isEmpty else { continue }
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        let apkData = try Data(contentsOf: apkURL)
        let filename = apkURL.lastPathComponent
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append(
            "Content-Disposition: form-data; name=\"apk\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!
        )
        body.append("Content-Type: application/vnd.android.package-archive\r\n\r\n".data(using: .utf8)!)
        body.append(apkData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        applyAuth(&req)
        req.httpBody = body
        req.timeoutInterval = 600
        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            if let obj = StoreOpsJSON.object(from: data),
               let msg = (obj["error"] as? [String: Any])?["message"] as? String {
                throw StoreOpsError.network("HTTP \(code): \(msg)")
            }
            throw StoreOpsError.http(code)
        }
        return data
    }

    private func applyAuth(_ req: inout URLRequest) {
        if let token = resolvedStaffToken() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.setValue("swift-client", forHTTPHeaderField: "X-Ops-Actor")
    }

    private func decodePackages(_ data: Data) throws -> [OpsPackage] {
        if let root = StoreOpsJSON.object(from: data),
           let arr = root["packages"] as? [[String: Any]] {
            return try arr.map(Self.package(from:))
        }
        throw StoreOpsError.decode("packages")
    }

    private func decodeDevices(_ data: Data) throws -> [OpsDevice] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = root["devices"] as? [[String: Any]] else {
            throw StoreOpsError.decode("devices")
        }
        return arr.compactMap { obj in
            guard let id = obj["id"] as? String else { return nil }
            return OpsDevice(
                id: id,
                label: obj["label"] as? String ?? id,
                platform: obj["platform"] as? String ?? "android",
                serial: obj["serial"] as? String,
                state: obj["state"] as? String ?? "unknown"
            )
        }
    }

    private func decodeDevice(_ data: Data) throws -> OpsDevice {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let obj = root["device"] as? [String: Any],
              let id = obj["id"] as? String else {
            throw StoreOpsError.decode("device")
        }
        return OpsDevice(
            id: id,
            label: obj["label"] as? String ?? id,
            platform: obj["platform"] as? String ?? "android",
            serial: obj["serial"] as? String,
            state: obj["state"] as? String ?? "unknown"
        )
    }

    private func decodeJobs(_ data: Data) throws -> [InstallJob] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = root["jobs"] as? [[String: Any]] else {
            throw StoreOpsError.decode("jobs")
        }
        return try arr.map(Self.job(from:))
    }

    private func decodeJobEnvelope(_ data: Data) throws -> InstallJob {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let obj = root["job"] as? [String: Any] else {
            throw StoreOpsError.decode("job")
        }
        return try Self.job(from: obj)
    }

    private static func job(from obj: [String: Any]) throws -> InstallJob {
        guard let id = obj["id"] as? String,
              let pkg = obj["package_name"] as? String ?? obj["packageName"] as? String,
              let dev = obj["device_id"] as? String ?? obj["deviceId"] as? String,
              let statusRaw = obj["status"] as? String,
              let status = InstallJobStatus(rawValue: statusRaw) else {
            throw StoreOpsError.decode("job fields")
        }
        return InstallJob(
            id: id,
            packageName: pkg,
            deviceId: dev,
            status: status,
            createdBy: obj["created_by"] as? String,
            error: obj["error"] as? String
        )
    }

    private static func package(from obj: [String: Any]) throws -> OpsPackage {
        let name = obj["package_name"] as? String ?? obj["packageName"] as? String
        guard let packageName = name else { throw StoreOpsError.decode("package_name") }
        let latest = obj["latest"] as? [String: Any]
        return OpsPackage(
            packageName: packageName,
            displayName: obj["display_name"] as? String ?? obj["displayName"] as? String ?? packageName,
            summary: obj["summary"] as? String ?? "",
            platform: obj["platform"] as? String ?? "android",
            versionName: latest?["version_name"] as? String ?? obj["version_name"] as? String,
            versionCode: latest?["version_code"] as? Int ?? obj["version_code"] as? Int,
            installURL: url(latest?["install_url"] ?? obj["install_url"]),
            artifactURL: url(latest?["artifact_url"] ?? obj["artifact_url"]),
            sizeBytes: (latest?["size_bytes"] as? Int).map(Int64.init)
                ?? (obj["size_bytes"] as? Int).map(Int64.init),
            status: obj["status"] as? String ?? "published"
        )
    }

    private static func url(_ any: Any?) -> URL? {
        guard let s = any as? String else { return nil }
        return URL(string: s)
    }

    private func decodeAudit(_ data: Data) throws -> [OpsAuditEvent] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = root["events"] as? [[String: Any]] else {
            throw StoreOpsError.decode("audit")
        }
        return arr.compactMap { obj in
            guard let id = obj["id"] as? String else { return nil }
            let meta = obj["meta"] as? [String: Any]
            return OpsAuditEvent(
                id: id,
                actor: obj["actor"] as? String ?? "?",
                action: obj["action"] as? String ?? "?",
                resourceType: obj["resource_type"] as? String
                    ?? obj["resourceType"] as? String ?? "?",
                resourceId: obj["resource_id"] as? String
                    ?? obj["resourceId"] as? String ?? "?",
                at: obj["at"] as? String,
                metaNote: meta?["note"] as? String
            )
        }
    }
}
