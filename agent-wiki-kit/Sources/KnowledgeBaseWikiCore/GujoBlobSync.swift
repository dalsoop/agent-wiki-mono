import SigV4Kit
import Foundation

/// gujo blobs 의 S3 왕복 — `blobs/<앞2자>/<sha256>` ↔ S3 키 동일 경로.
/// 2026-08 저장소는 Cloudflare R2(옛 garage 이전, 동일 버킷명·키 레이아웃).
///
/// 내용주소라 어디서 받든 sha256 재계산으로 무결성이 자동 검증된다. push 는 로컬에만
/// 있는 blob 을 올리고, pull 은 원격에만 있는 blob 을 받는다 — 양쪽 다 append-only 라
/// 삭제 연산이 없다(prune 은 별도 정책). 외부 의존 0: URLSession + `SigV4Kit` 로
/// 서명한다(publish-kit S3Publisher 와 같은 정본; R2 는 AWS SigV4 호환).
public struct GujoBlobSync: Sendable {
    public let root: URL
    public let config: GujoBlobConfig
    let store: BlobStore

    public init(root: URL, config: GujoBlobConfig) {
        self.root = root
        self.config = config
        self.store = BlobStore(root: root)
    }

    // MARK: - 설정

    /// 자격 로드 우선순위: env(GUJO_S3_*) → `<root>/.git/gujo-s3.json`(0600, git 밖).
    /// endpoint 기본은 R2(계정 전용 S3 엔드포인트, region `auto`).
    public static func loadConfig(root: URL) -> GujoBlobConfig? {
        GujoBlobConfig.load(root: root)
    }

    // MARK: - 계획 (로컬 ↔ 원격 차집합)

    public struct Plan: Codable, Sendable, Equatable {
        public var localCount: Int
        public var remoteCount: Int
        /// 원격에만 있음 — pull 대상.
        public var missingLocal: [String]
        /// 로컬에만 있음 — push 대상.
        public var missingRemote: [String]
    }

    public static func plan(local: [String], remote: [String]) -> Plan {
        let localSet = Set(local), remoteSet = Set(remote)
        return Plan(
            localCount: local.count, remoteCount: remote.count,
            missingLocal: remoteSet.subtracting(localSet).sorted(),
            missingRemote: localSet.subtracting(remoteSet).sorted())
    }

    public func plan() -> Result<Plan, GujoError> {
        switch listRemote() {
        case .failure(let error): return .failure(error)
        case .success(let remote):
            let plan = Self.plan(local: store.allSHAs(), remote: remote)
            stampMissing(plan.missingLocal.count)
            return .success(plan)
        }
    }

    /// 마지막으로 관측한 "원격에만 있는 blob 수" — status/StateMirror 가 네트워크 없이
    /// 읽는다(syncthing 실패 비가시성 사고의 재발 방지 장치. 관측이 먼저다).
    var missingMarker: URL { root.appendingPathComponent(".git/gujo-blobs-missing") }

    func stampMissing(_ count: Int) {
        do { try String(count).write(to: missingMarker, atomically: true, encoding: .utf8) } catch { _ = error }
    }

    public static func lastKnownMissing(root: URL) -> Int? {
        let marker = root.appendingPathComponent(".git/gujo-blobs-missing")
        guard let raw = try? String(contentsOf: marker, encoding: .utf8) else { return nil }
        return Int(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - 원격 나열 (ListObjectsV2)

    public func listRemote() -> Result<[String], GujoError> {
        var shas: [String] = []
        var token: String?
        repeat {
            var query = [("list-type", "2")]
            if let token { query.append(("continuation-token", token)) }
            switch request(method: "GET", key: nil, query: query, body: nil) {
            case .failure(let error): return .failure(error)
            case .success(let data):
                let xml = String(decoding: data, as: UTF8.self)
                for key in Self.xmlValues(xml, tag: "Key") {
                    let sha = String(key.split(separator: "/").last ?? "")
                    if sha.count == 64 { shas.append(sha) }
                }
                token = Self.xmlValues(xml, tag: "NextContinuationToken").first
                if !xml.contains("<IsTruncated>true</IsTruncated>") { token = nil }
            }
        } while token != nil
        return .success(shas.sorted())
    }

    /// S3 응답 XML 에서 <tag>…</tag> 값들. 키는 hex/슬래시뿐이라 정규식으로 충분하다.
    static func xmlValues(_ xml: String, tag: String) -> [String] {
        var out: [String] = []
        var rest = Substring(xml)
        while let open = rest.range(of: "<\(tag)>"), let close = rest.range(of: "</\(tag)>"),
              open.upperBound <= close.lowerBound {
            out.append(String(rest[open.upperBound..<close.lowerBound]))
            rest = rest[close.upperBound...]
        }
        return out
    }

    // MARK: - 왕복

    public struct Outcome: Codable, Sendable, Equatable {
        public var transferred: [String]
        public var skipped: Int
        public var failed: [String]
        public var bytes: Int
    }

    /// 원격 → 로컬. `shas` 를 주면 그것만, 없으면 빠진 것 전부. 받은 바이트는
    /// sha256 재계산으로 검증 후 저장(불일치면 버리고 failed 에 기록).
    public func pull(shas requested: [String]? = nil) -> Result<Outcome, GujoError> {
        let targets: [String]
        if let requested {
            targets = requested
        } else {
            switch plan() {
            case .failure(let error): return .failure(error)
            case .success(let plan): targets = plan.missingLocal
            }
        }
        var outcome = Outcome(transferred: [], skipped: 0, failed: [], bytes: 0)
        for sha in targets {
            if store.exists(sha) { outcome.skipped += 1; continue }
            switch request(method: "GET", key: sha, query: [], body: nil) {
            case .failure:
                outcome.failed.append(sha)
            case .success(let data):
                if BlobStore.sha256(data) == sha, (try? store.put(data)) != nil {
                    outcome.transferred.append(sha)
                    outcome.bytes += data.count
                } else {
                    outcome.failed.append(sha)  // 위조/전송 오류 — 저장하지 않는다
                }
            }
        }
        if outcome.failed.isEmpty, requested == nil { stampMissing(0) }
        return .success(outcome)
    }

    /// 로컬 → 원격. 업로드 전 로컬 파일 무결성을 먼저 검증한다(변조 blob 전파 방지).
    public func push(shas requested: [String]? = nil) -> Result<Outcome, GujoError> {
        let targets: [String]
        if let requested {
            targets = requested
        } else {
            switch plan() {
            case .failure(let error): return .failure(error)
            case .success(let plan): targets = plan.missingRemote
            }
        }
        var outcome = Outcome(transferred: [], skipped: 0, failed: [], bytes: 0)
        for sha in targets {
            guard let data = store.get(sha), BlobStore.sha256(data) == sha else {
                outcome.failed.append(sha)
                continue
            }
            switch request(method: "PUT", key: sha, query: [], body: data) {
            case .failure: outcome.failed.append(sha)
            case .success:
                outcome.transferred.append(sha)
                outcome.bytes += data.count
            }
        }
        return .success(outcome)
    }

    // MARK: - S3 요청 (SigV4 헤더 서명)

    func request(method: String, key: String?, query: [(String, String)], body: Data?)
        -> Result<Data, GujoError> {
        guard let endpoint = URL(string: config.endpoint), let host = endpoint.host else {
            return .failure(.refused("endpoint 가 URL 이 아니다: \(config.endpoint)"))
        }
        var path = "/\(config.bucket)"
        if let key { path += "/\(key.prefix(2))/\(key)" }
        let canonicalQuery = SigV4Signer.canonicalQuery(query)
        // 서명 대상 페이로드 해시 — blob PUT 은 내용주소라 해시가 곧 키와 일치해야 한다.
        let payloadHash = body.map { BlobStore.sha256($0) } ?? Self.emptyPayloadHash
        let amzDate = Self.amzDateFormatter.string(from: Date())
        let auth = Self.authorization(GujoSigV4Input(
            method: method, path: path, query: canonicalQuery, host: host,
            payloadHash: payloadHash, amzDate: amzDate,
            region: config.region, accessKey: config.accessKey, secretKey: config.secretKey))

        var components = URLComponents()
        components.scheme = endpoint.scheme
        components.host = host
        components.port = endpoint.port
        components.percentEncodedPath = path
        if !canonicalQuery.isEmpty { components.percentEncodedQuery = canonicalQuery }
        guard let url = components.url else { return .failure(.refused("URL 조립 실패")) }

        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        request.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")
        request.setValue(auth, forHTTPHeaderField: "Authorization")

        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: Result<Data, GujoError> = .failure(.unreachable("응답 없음"))
        URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error {
                result = .failure(.unreachable("S3 도달 실패: \(error.localizedDescription)"))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                result = .failure(.unreachable("HTTP 응답 아님"))
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                let detail = String(decoding: (data ?? Data()).prefix(300), as: UTF8.self)
                result = .failure(.git("S3 \(http.statusCode): \(detail)"))
                return
            }
            result = .success(data ?? Data())
        }.resume()
        semaphore.wait()
        return result
    }

    // MARK: - SigV4 (서명은 `SigV4Kit` 정본에 위임; 순수 함수라 테스트가 직접 친다)

    /// 빈 페이로드 해시 — `SigV4Kit` 정본.
    public static let emptyPayloadHash = SigV4Signer.emptyPayloadHash

    static let amzDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// AWS SigV4 Authorization 헤더 — `SigV4Kit.SigV4Signer` 에 위임(구현 중복 제거).
    /// 입력 계약(method/path/query/host/payloadHash/amzDate/region/keys) 은 그대로 —
    /// 테스트가 파이썬 벡터로 고정한 출력과 동일해야 한다.
    public static func authorization(_ input: GujoSigV4Input) -> String {
        let datestamp = String(input.amzDate.prefix(8))
        let signer = SigV4Signer(
            accessKey: input.accessKey, secretKey: input.secretKey,
            region: input.region, service: "s3")
        return signer.authorization(
            method: input.method, canonicalUri: input.path, canonicalQueryString: input.query,
            headers: [
                ("host", input.host),
                ("x-amz-content-sha256", input.payloadHash),
                ("x-amz-date", input.amzDate),
            ],
            payloadHash: input.payloadHash, amzDate: input.amzDate, dateStamp: datestamp)
    }

    /// 하위호환 — 축을 직접 나열하는 옛 호출부(테스트 벡터 등)도 그대로 컴파일된다.
    /// 새 코드는 `GujoSigV4Input` 을 구성해 넘긴다.
    public static func authorization(
        method: String, path: String, query: String, host: String,
        payloadHash: String, amzDate: String,
        region: String, accessKey: String, secretKey: String
    ) -> String {
        authorization(GujoSigV4Input(
            method: method, path: path, query: query, host: host,
            payloadHash: payloadHash, amzDate: amzDate,
            region: region, accessKey: accessKey, secretKey: secretKey))
    }
}

public struct GujoSigV4Input: Sendable, Equatable {
    public var method: String
    public var path: String
    public var query: String
    public var host: String
    public var payloadHash: String
    public var amzDate: String
    public var region: String
    public var accessKey: String
    public var secretKey: String
}

/// blob 스토리지 접속 자격 — env(GUJO_S3_*) 우선, `<root>/.git/gujo-s3.json`(0600) 폴백.
/// `.git/` 안이라 커밋될 수 없다(gujo-last-sync 마커와 같은 규율).
public struct GujoBlobConfig: Codable, Sendable, Equatable {
    public var endpoint: String
    public var bucket: String
    public var region: String
    public var accessKey: String
    public var secretKey: String

    public init(endpoint: String = "https://3512fb9ec3513c795ed6293dc7210a8c.r2.cloudflarestorage.com",
                bucket: String = "gujo-wiki-blobs",
                region: String = "auto",
                accessKey: String, secretKey: String) {
        self.endpoint = endpoint
        self.bucket = bucket
        self.region = region
        self.accessKey = accessKey
        self.secretKey = secretKey
    }

    public static func fileURL(root: URL) -> URL {
        root.appendingPathComponent(".git/gujo-s3.json")
    }

    public static func load(root: URL) -> GujoBlobConfig? {
        let env = ProcessInfo.processInfo.environment
        if let accessKey = env["GUJO_S3_ACCESS_KEY"], let secretKey = env["GUJO_S3_SECRET_KEY"],
           !accessKey.isEmpty, !secretKey.isEmpty {
            return GujoBlobConfig(
                endpoint: env["GUJO_S3_ENDPOINT"] ?? "https://3512fb9ec3513c795ed6293dc7210a8c.r2.cloudflarestorage.com",
                bucket: env["GUJO_S3_BUCKET"] ?? "gujo-wiki-blobs",
                region: env["GUJO_S3_REGION"] ?? "auto",
                accessKey: accessKey, secretKey: secretKey)
        }
        guard let data = try? Data(contentsOf: fileURL(root: root)) else { return nil }
        do {
            return try JSONDecoder().decode(GujoBlobConfig.self, from: data)
        } catch {
            return nil
        }
    }

    public func save(root: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let url = Self.fileURL(root: root)
        try encoder.encode(self).write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
