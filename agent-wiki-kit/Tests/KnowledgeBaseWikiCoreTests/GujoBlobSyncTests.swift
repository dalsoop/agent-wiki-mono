import Foundation
import Testing
@testable import KnowledgeBaseWikiCore

/// gujo blobs 의 garage(S3) 왕복 계약. 서명은 고정 벡터로 검증한다 — 네트워크 없이
/// SigV4 구현이 표준과 일치함을 못박는다(벡터는 파이썬 hmac/hashlib 로 독립 계산).
@Suite struct GujoBlobSyncTests {
    // MARK: - SigV4

    @Test func sigV4MatchesIndependentlyComputedVector() {
        let auth = GujoBlobSync.authorization(GujoSigV4Input(
            method: "GET", path: "/gujo-wiki-blobs/ab/abcdef", query: "",
            host: "s3.test.internal",
            payloadHash: GujoBlobSync.emptyPayloadHash,
            amzDate: "20260729T120000Z",
            region: "garage", accessKey: "GKTESTKEY", secretKey: "testsecret"))
        #expect(auth.contains("Credential=GKTESTKEY/20260729/garage/s3/aws4_request"))
        #expect(auth.contains("SignedHeaders=host;x-amz-content-sha256;x-amz-date"))
        // 파이썬 독립 계산값 — 구현이 바뀌어 서명이 달라지면 여기서 잡힌다.
        #expect(auth.hasSuffix(
            "Signature=abee38634d9e2bc60168a727d39a25b0d51352c90df89c9542c378f83e70dc4c"))
    }

    @Test func sigV4WithQueryMatchesVector() {
        let auth = GujoBlobSync.authorization(GujoSigV4Input(
            method: "GET", path: "/gujo-wiki-blobs", query: "list-type=2&prefix=",
            host: "s3.test.internal",
            payloadHash: GujoBlobSync.emptyPayloadHash,
            amzDate: "20260729T120000Z",
            region: "garage", accessKey: "GKTESTKEY", secretKey: "testsecret"))
        #expect(auth.hasSuffix(
            "Signature=1438379319ce161c333b136cddbea274e5694dcadf303dd75d0759a47cf12245"))
    }

    // MARK: - 계획(차집합)

    @Test func planComputesSetDifferences() {
        let plan = GujoBlobSync.plan(
            local: ["aa", "bb", "cc"], remote: ["bb", "cc", "dd", "ee"])
        #expect(plan.localCount == 3)
        #expect(plan.remoteCount == 4)
        #expect(plan.missingLocal == ["dd", "ee"])   // pull 대상
        #expect(plan.missingRemote == ["aa"])         // push 대상
    }

    // MARK: - ListObjectsV2 XML

    @Test func xmlValuesExtractsKeysAndContinuation() {
        let xml = """
        <?xml version="1.0"?><ListBucketResult>
        <IsTruncated>true</IsTruncated>
        <Contents><Key>03/039a415f</Key></Contents>
        <Contents><Key>09/091d5690</Key></Contents>
        <NextContinuationToken>tok123</NextContinuationToken>
        </ListBucketResult>
        """
        #expect(GujoBlobSync.xmlValues(xml, tag: "Key") == ["03/039a415f", "09/091d5690"])
        #expect(GujoBlobSync.xmlValues(xml, tag: "NextContinuationToken") == ["tok123"])
        #expect(GujoBlobSync.xmlValues(xml, tag: "Missing").isEmpty)
    }

    // MARK: - 자격 저장/로드

    /// 기본 저장소는 R2 다(2026-08 garage→R2 전환). 기본값이 우연히 되돌아가면
    /// 자격 없는 신규 온보딩이 죽은 내부 ingress 를 보게 된다 — 여기서 못박는다.
    @Test func configDefaultsPointAtR2() {
        let config = GujoBlobConfig(accessKey: "k", secretKey: "s")
        #expect(config.endpoint == "https://3512fb9ec3513c795ed6293dc7210a8c.r2.cloudflarestorage.com")
        #expect(config.region == "auto")
        #expect(config.bucket == "gujo-wiki-blobs")
    }

    @Test func configRoundtripsThroughGitDirFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("gujo-blob-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let config = GujoBlobConfig(accessKey: "GKx", secretKey: "sk")
        try config.save(root: root)
        // env 가 없을 때 파일 폴백으로 동일하게 복원돼야 한다.
        #expect(GujoBlobConfig.load(root: root) == config)
        // .git 안(커밋 불가) + 0600 — 자격이 원장에 실리지 않는다.
        let path = GujoBlobConfig.fileURL(root: root).path
        #expect(path.contains("/.git/"))
        let perms = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
        #expect(perms == 0o600)
    }

    // MARK: - 뒤처짐 관측 (missing 마커)

    @Test func missingMarkerFeedsStatusWithoutNetwork() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("gujo-blob-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(GujoBlobSync.lastKnownMissing(root: root) == nil)
        let blob = GujoBlobSync(root: root, config: GujoBlobConfig(accessKey: "a", secretKey: "b"))
        blob.stampMissing(7)
        #expect(GujoBlobSync.lastKnownMissing(root: root) == 7)
    }

    // MARK: - wiki-hub 응답 계약

    @Test func hubUsesCanonicalWikiHostname() {
        #expect(GujoHubClient.defaultBaseURL.absoluteString == "https://wiki.50.internal.kr")
    }

    /// wiki-hub(wiki.50.internal.kr)가 내보내는 JSON 이 FleetPullResult 로 그대로
    /// 디코드돼야 한다 — 서버는 파이썬, 클라이언트는 Swift 지만 계약은 하나다.
    @Test func hubSearchResponseDecodesAsFleetPullResult() throws {
        let json = """
        {"agent": "gujo-wiki-hub", "query": "백업", "maxObjects": 2, "truncated": true,
         "items": [{"world": "gujo-wiki",
                    "id": "8f5cf2f4b12ba6b8db4d8a412b8a1e11d0cd60c1b43c4d7a426004d4c011b6df",
                    "snippet": "백업 키 단일점 문제", "body": "본문…",
                    "title": "결정: 백업 비암호화 방침", "score": 4.2707}]}
        """
        let decoded = try JSONDecoder().decode(FleetPullResult.self, from: Data(json.utf8))
        #expect(decoded.agent == "gujo-wiki-hub")
        #expect(decoded.truncated)
        #expect(decoded.items.count == 1)
        #expect(decoded.items[0].world == "gujo-wiki")
        #expect(decoded.items[0].score == 4.2707)
        #expect(decoded.events == nil)
    }

    @Test func hubEventsResponseDecodesAsFleetPullResult() throws {
        let json = """
        {"agent": "gujo-wiki-hub", "maxObjects": 20, "truncated": false, "items": [],
         "events": [{"id": "019f8138-f174-78dc-86f7-235cd8cfc590",
                     "subject": "wiki-maintainer", "rel": "시도 2 타임아웃",
                     "level": "step", "parent": "019f8101-e042-7bda-bb79-50ba715780d2"}],
         "blobShas": ["039a415f252c1ecf00f01ae0793de9c6e6f5c4df51a3d6082e17432554aae6dd"]}
        """
        let decoded = try JSONDecoder().decode(FleetPullResult.self, from: Data(json.utf8))
        #expect(decoded.items.isEmpty)
        #expect(decoded.events?.count == 1)
        #expect(decoded.events?[0].level == "step")
        #expect(decoded.blobShas?.count == 1)
    }
}
