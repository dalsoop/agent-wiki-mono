import Foundation
import XCTest
@testable import ShareLinkKit

/// BYO 저장소 공유 링크.
///
/// S3 호환 저장소는 **틀려도 403 만 오고 이유는 안 온다.** path-style/virtual-host,
/// canonical URI 인코딩, `x-amz-content-sha256` 누락 — 전부 같은 증상으로 실패한다.
/// 그래서 요청 조립을 네트워크에서 떼어 내 여기서 못 박는다.
final class ShareLinkKitTests: XCTestCase {

    private func target(
        endpoint: String = "https://s3.example.com",
        bucket: String = "shots",
        publicBase: String = "",
        prefix: String = "",
        pathStyle: Bool = true
    ) -> ShareTarget {
        ShareTarget(
            endpoint: endpoint, bucket: bucket, region: "us-east-1",
            publicBaseURL: publicBase, pathPrefix: prefix, usesPathStyle: pathStyle,
            credentialProfile: "share-storage"
        )
    }

    private let fixedDate = Date(timeIntervalSince1970: 1_760_000_000)

    // MARK: - 설정 검증

    func testEmptyTargetNamesEveryMissingField() {
        let missing = ShareTarget().missingFields
        XCTAssertTrue(missing.contains(.endpoint))
        XCTAssertTrue(missing.contains(.bucket))
        XCTAssertFalse(
            missing.contains(.region), "리전은 기본값이 있다 — 없다고 하면 사용자가 헷갈린다"
        )
    }

    /// 사용자는 주소를 복사해 붙인다 — 끝 슬래시가 따라오는 게 보통이다.
    func testTrailingSlashesAndSpacesAreForgiven() {
        var t = target(endpoint: "  https://s3.example.com/  ")
        t.publicBaseURL = "https://cdn.example.com//"
        XCTAssertTrue(t.isConfigured)
        let url = try? ShareRequestBuilder.publicURL(target: t, objectKey: "a/b.png")
        XCTAssertEqual(url?.absoluteString, "https://cdn.example.com/a/b.png")
    }

    func testIncompleteTargetIsRejectedBeforeAnyNetworkCall() {
        XCTAssertThrowsError(
            try ShareRequestBuilder.uploadURL(target: ShareTarget(), objectKey: "a.png")
        ) { error in
            guard case ShareRequestBuilder.BuildError.incompleteTarget(let fields)? =
                    error as? ShareRequestBuilder.BuildError else {
                return XCTFail("설정 부족을 짚어 주지 않는다: \(error)")
            }
            XCTAssertFalse(fields.isEmpty)
        }
    }

    // MARK: - 주소 형태 (path-style vs virtual-host)

    /// 자체 호스팅(MinIO·Garage)은 대개 path-style 이라야 한다. 틀리면 404/403 만 온다.
    func testPathStylePutsTheBucketInThePath() throws {
        let url = try ShareRequestBuilder.uploadURL(
            target: target(pathStyle: true), objectKey: "2026/08/abc.png"
        )
        XCTAssertEqual(url.absoluteString, "https://s3.example.com/shots/2026/08/abc.png")
    }

    func testVirtualHostStylePutsTheBucketInTheHost() throws {
        let url = try ShareRequestBuilder.uploadURL(
            target: target(pathStyle: false), objectKey: "2026/08/abc.png"
        )
        XCTAssertEqual(url.absoluteString, "https://shots.s3.example.com/2026/08/abc.png")
    }

    /// 서명에 쓰는 canonical URI 는 주소 형태에 따라 버킷을 포함하거나 빼야 한다.
    func testCanonicalURIFollowsTheAddressStyle() {
        XCTAssertEqual(
            ShareRequestBuilder.canonicalURI(target: target(pathStyle: true), objectKey: "a/b.png"),
            "/shots/a/b.png"
        )
        XCTAssertEqual(
            ShareRequestBuilder.canonicalURI(target: target(pathStyle: false), objectKey: "a/b.png"),
            "/a/b.png"
        )
    }

    /// 세그먼트는 인코딩하되 구분자 `/` 는 남긴다 — 슬래시까지 인코딩하면 키가 달라진다.
    func testCanonicalURIEncodesSegmentsButKeepsSeparators() {
        let uri = ShareRequestBuilder.canonicalURI(
            target: target(pathStyle: false), objectKey: "2026/08/a b+c.png"
        )
        XCTAssertEqual(uri, "/2026/08/a%20b%2Bc.png")
    }

    /// 기본 포트를 host 헤더에 붙이면 서명과 실제 요청이 달라져 403 이 난다.
    func testDefaultPortsAreNotPutInTheHostHeader() {
        XCTAssertEqual(ShareRequestBuilder.hostHeader(host: "s3.example.com", port: 443), "s3.example.com")
        XCTAssertEqual(ShareRequestBuilder.hostHeader(host: "s3.example.com", port: nil), "s3.example.com")
        XCTAssertEqual(
            ShareRequestBuilder.hostHeader(host: "localhost", port: 9000), "localhost:9000",
            "비표준 포트는 붙여야 서명이 맞는다"
        )
    }

    // MARK: - 서명된 요청

    func testUploadRequestCarriesTheHeadersS3Requires() throws {
        let request = try ShareRequestBuilder.uploadRequest(
            target: target(), objectKey: "a.png", body: Data("hello".utf8),
            contentType: "image/png", accessKey: "AKIA", secretKey: "secret", date: fixedDate
        )
        XCTAssertEqual(request.httpMethod, "PUT")
        // 이 헤더가 없으면 요청 자체가 거부된다.
        XCTAssertNotNil(request.value(forHTTPHeaderField: "x-amz-content-sha256"))
        XCTAssertNotNil(request.value(forHTTPHeaderField: "x-amz-date"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "content-type"), "image/png")
        let auth = try XCTUnwrap(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(auth.hasPrefix("AWS4-HMAC-SHA256 Credential=AKIA/"))
        XCTAssertTrue(auth.contains("SignedHeaders="))
        XCTAssertTrue(auth.contains("Signature="))
    }

    /// 서명 대상 헤더 목록에 host 가 빠지면 대부분의 저장소가 거절한다.
    func testHostIsSigned() throws {
        let request = try ShareRequestBuilder.uploadRequest(
            target: target(), objectKey: "a.png", body: Data(), contentType: "image/png",
            accessKey: "AKIA", secretKey: "secret", date: fixedDate
        )
        let auth = try XCTUnwrap(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(auth.contains("host"), "SignedHeaders 에 host 가 없다")
    }

    /// 같은 입력이면 같은 서명이 나와야 한다(시각을 고정했을 때).
    func testSignatureIsDeterministicForTheSameInput() throws {
        func sign() throws -> String {
            let request = try ShareRequestBuilder.uploadRequest(
                target: target(), objectKey: "a.png", body: Data("x".utf8),
                contentType: "image/png", accessKey: "AKIA", secretKey: "secret", date: fixedDate
            )
            return request.value(forHTTPHeaderField: "Authorization") ?? ""
        }
        XCTAssertEqual(try sign(), try sign())
    }

    func testDifferentBodiesProduceDifferentSignatures() throws {
        func sign(_ body: String) throws -> String {
            try ShareRequestBuilder.uploadRequest(
                target: target(), objectKey: "a.png", body: Data(body.utf8),
                contentType: "image/png", accessKey: "AKIA", secretKey: "secret", date: fixedDate
            ).value(forHTTPHeaderField: "Authorization") ?? ""
        }
        XCTAssertNotEqual(try sign("a"), try sign("b"), "본문 해시가 서명에 안 들어갔다")
    }

    func testAmzDateIsUTCInTheFormatS3Expects() {
        let stamp = ShareRequestBuilder.amzDate(Date(timeIntervalSince1970: 0))
        XCTAssertEqual(stamp, "19700101T000000Z")
    }

    // MARK: - 만료 링크 (presigned)

    /// 버킷을 공개로 열 수 없을 때 쓴다 — 권한이 링크 자체에 실린다.
    func testPresignedLinkCarriesEverythingS3NeedsToVerifyIt() throws {
        let url = try ShareRequestBuilder.presignedURL(
            target: target(), objectKey: "a/b.png", accessKey: "AKIA",
            secretKey: "secret", date: fixedDate, expiresIn: 3600
        )
        let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.query)
        for parameter in [
            "X-Amz-Algorithm=AWS4-HMAC-SHA256", "X-Amz-Credential=AKIA",
            "X-Amz-Date=", "X-Amz-Expires=3600", "X-Amz-SignedHeaders=host",
            "X-Amz-Signature=",
        ] {
            XCTAssertTrue(query.contains(parameter), "\(parameter) 가 빠졌다 — 링크가 거부된다")
        }
    }

    /// S3 가 허용하는 만료 상한은 7일이다. 넘겨 주면 **요청 자체가 거절**된다.
    func testExpiryIsCappedAtWhatS3Accepts() throws {
        let url = try ShareRequestBuilder.presignedURL(
            target: target(), objectKey: "a.png", accessKey: "AKIA", secretKey: "secret",
            date: fixedDate, expiresIn: 60 * 60 * 24 * 400
        )
        let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.query)
        XCTAssertTrue(query.contains("X-Amz-Expires=604800"), "7일을 넘겨 서명하면 거절된다")
    }

    func testPresignedSignatureChangesWithTheObject() throws {
        func sign(_ key: String) throws -> String {
            try ShareRequestBuilder.presignedURL(
                target: target(), objectKey: key, accessKey: "AKIA", secretKey: "secret",
                date: fixedDate, expiresIn: 600
            ).absoluteString
        }
        XCTAssertNotEqual(try sign("a.png"), try sign("b.png"))
    }

    /// 설정이 만료를 요구하면 업로더가 공개 주소 대신 서명 링크를 준다.
    func testUploaderHonoursTheExpirySetting() async throws {
        var configured = target(publicBase: "https://cdn.example.com")
        configured.linkExpirySeconds = 900
        let uploader = ShareUploader { request in
            (Data(), HTTPURLResponse(url: request.url!, statusCode: 200,
                                     httpVersion: nil, headerFields: nil)!)
        }
        let url = try await uploader.upload(
            Data("png".utf8), contentType: "image/png", fileExtension: "png",
            target: configured,
            credentials: [
                ShareCredential.accessKeyField: "AKIA",
                ShareCredential.secretKeyField: "s3cret",
            ],
            date: fixedDate
        )
        XCTAssertTrue(url.absoluteString.contains("X-Amz-Signature="))
        // 서명은 호스트·경로에 묶인다 — CDN 도메인으로 갈아 끼우면 서명이 안 맞는다.
        XCTAssertFalse(
            url.absoluteString.hasPrefix("https://cdn.example.com"),
            "만료 링크에 앞단 도메인을 붙이면 서명이 깨진다"
        )
    }

    func testZeroOrNegativeExpiryFallsBackToThePublicLink() async throws {
        var configured = target(publicBase: "https://cdn.example.com")
        configured.linkExpirySeconds = 0
        let uploader = ShareUploader { request in
            (Data(), HTTPURLResponse(url: request.url!, statusCode: 200,
                                     httpVersion: nil, headerFields: nil)!)
        }
        let url = try await uploader.upload(
            Data(), contentType: "image/png", fileExtension: "png", target: configured,
            credentials: [
                ShareCredential.accessKeyField: "AKIA",
                ShareCredential.secretKeyField: "s3cret",
            ],
            date: fixedDate
        )
        XCTAssertTrue(url.absoluteString.hasPrefix("https://cdn.example.com"))
        XCTAssertFalse(url.absoluteString.contains("X-Amz-Signature="))
    }

    // MARK: - 오브젝트 키

    /// 공유 링크는 대개 인증 없이 열린다 — 날짜와 순번만 쓰면 남의 캡처 주소를
    /// 손으로 만들어 볼 수 있다.
    func testKeysAreNotGuessable() {
        let keys = (0..<50).map { _ in
            ShareObjectKey.make(prefix: "shots", fileExtension: "png", date: fixedDate)
        }
        XCTAssertEqual(Set(keys).count, keys.count, "같은 키가 두 번 나왔다")
        let random = keys[0].split(separator: "/").last?.split(separator: ".").first ?? ""
        XCTAssertGreaterThanOrEqual(random.count, 16, "짧으면 추측된다")
    }

    func testKeyIsGroupedByYearAndMonth() {
        let key = ShareObjectKey.make(
            prefix: "shots", fileExtension: "png",
            date: Date(timeIntervalSince1970: 0), randomProvider: { "FIXED" }
        )
        XCTAssertEqual(key, "shots/1970/01/FIXED.png")
    }

    /// 사용자가 `/screenshots/` 처럼 적어도 그대로 동작해야 한다.
    func testPrefixSlashesAndOddCharactersAreCleanedUp() {
        let key = ShareObjectKey.make(
            prefix: "/my shots//", fileExtension: "PNG",
            date: Date(timeIntervalSince1970: 0), randomProvider: { "X" }
        )
        XCTAssertEqual(key, "myshots/1970/01/X.png")
    }

    func testEmptyPrefixJustDropsThatSegment() {
        let key = ShareObjectKey.make(
            prefix: "", fileExtension: "gif",
            date: Date(timeIntervalSince1970: 0), randomProvider: { "X" }
        )
        XCTAssertEqual(key, "1970/01/X.gif")
    }

    // MARK: - 카드

    func testCardNeedsBothKeys() {
        XCTAssertNil(ShareCredential.keys(from: [:]))
        XCTAssertNil(ShareCredential.keys(from: [ShareCredential.accessKeyField: "AKIA"]))
        XCTAssertNil(
            ShareCredential.keys(from: [
                ShareCredential.accessKeyField: "AKIA",
                ShareCredential.secretKeyField: "   ",
            ]),
            "공백만 든 값은 없는 것과 같다 — 한쪽만 있으면 서명이 조용히 실패한다"
        )
        XCTAssertNotNil(ShareCredential.keys(from: [
            ShareCredential.accessKeyField: "AKIA",
            ShareCredential.secretKeyField: "s3cret",
        ]))
    }

    func testCardSpecAsksForBothKeysAndHidesTheSecret() {
        let spec = ShareCredential.spec()
        XCTAssertEqual(spec.fields.map(\.key), [
            ShareCredential.accessKeyField, ShareCredential.secretKeyField,
        ])
        XCTAssertEqual(spec.fields.last?.secret, true, "Secret 이 화면에 그대로 보이면 안 된다")
        XCTAssertEqual(spec.storage, .keychain, "설정 파일에 두면 백업·동기화로 새어 나간다")
    }

    // MARK: - 업로드 (전송 seam)

    func testSuccessfulUploadReturnsThePublicLink() async throws {
        let uploader = ShareUploader { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (Data(), response)
        }
        let url = try await uploader.upload(
            Data("png".utf8), contentType: "image/png", fileExtension: "png",
            target: target(publicBase: "https://cdn.example.com", prefix: "shots"),
            credentials: [
                ShareCredential.accessKeyField: "AKIA",
                ShareCredential.secretKeyField: "s3cret",
            ],
            date: fixedDate
        )
        XCTAssertTrue(url.absoluteString.hasPrefix("https://cdn.example.com/shots/"))
        XCTAssertTrue(url.absoluteString.hasSuffix(".png"))
    }

    /// 저장소는 거절 이유를 **본문**에 담아 보낸다. 상태 코드만 보여 주면 "403" 만 남아
    /// 버킷 권한인지 서명 문제인지 알 수 없다.
    func testRejectionCarriesTheStorageExplanation() async {
        let uploader = ShareUploader { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil
            )!
            return (Data("<Error><Code>SignatureDoesNotMatch</Code></Error>".utf8), response)
        }
        do {
            _ = try await uploader.upload(
                Data(), contentType: "image/png", fileExtension: "png", target: target(),
                credentials: [
                    ShareCredential.accessKeyField: "AKIA",
                    ShareCredential.secretKeyField: "s3cret",
                ],
                date: fixedDate
            )
            XCTFail("거절인데 성공했다")
        } catch {
            let message = error.localizedDescription
            XCTAssertTrue(message.contains("403"))
            XCTAssertTrue(
                message.contains("SignatureDoesNotMatch"),
                "저장소가 말해 준 이유를 버렸다: \(message)"
            )
        }
    }

    func testMissingCardIsReportedBeforeUploading() async {
        final class Probe: @unchecked Sendable { var sent = false }
        let probe = Probe()
        let uploader = ShareUploader { request in
            probe.sent = true
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 200,
                                            httpVersion: nil, headerFields: nil)!)
        }
        do {
            _ = try await uploader.upload(
                Data(), contentType: "image/png", fileExtension: "png",
                target: target(), credentials: [:], date: fixedDate
            )
            XCTFail("카드가 없는데 올렸다")
        } catch {
            XCTAssertFalse(probe.sent, "카드도 없이 저장소를 두드렸다")
            XCTAssertTrue(error.localizedDescription.contains("share-storage"))
        }
    }
}
