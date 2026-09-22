import Testing
import Foundation
@testable import SigV4Kit

/// AWS SigV4 서명 검증 — AWS 가 공개하는 sig-v4-test-suite `get-vanilla` 벡터로 전체
/// HMAC 체인·canonical request 구성을 고정한다. 이 벡터가 통과하면 S3/Garage 호출에
/// 쓰이는 서명 경로도(같은 알고리즘) 정확하다.
@Suite("SigV4")
struct SigV4KitTests {

    /// AWS sig-v4-test-suite / get-vanilla — service "service", region us-east-1.
    /// 헤더 host + x-amz-date(둘뿐). 정닰 시그니처로 전체 알고리즘을 잠근다.
    @Test("get-vanilla 공식 벡터 — 시그니처 정답 일치")
    func getVanillaVector() {
        let signer = SigV4Signer(
            accessKey: "AKIDEXAMPLE",
            secretKey: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
            region: "us-east-1",
            service: "service"
        )
        let auth = signer.authorization(
            method: "GET",
            canonicalUri: "/",
            canonicalQueryString: "",
            headers: [("host", "example.amazonaws.com"), ("x-amz-date", "20150830T123600Z")],
            payloadHash: SigV4Signer.emptyPayloadHash,
            amzDate: "20150830T123600Z",
            dateStamp: "20150830"
        )
        #expect(auth == "AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20150830/us-east-1/service/aws4_request, SignedHeaders=host;x-amz-date, Signature=5fa00fa31553b73ebf1942676e86291e8372ff2a2260956d9b8aae1d763fbf31")
    }

    /// S3 호출처가 쓰는 헤더 모양(host·x-amz-content-sha256·x-amz-date) — SignedHeaders 순서·구조.
    @Test("S3 3-헤더 모양 — SignedHeaders 와 스코프 형식")
    func s3HeaderShape() {
        let signer = SigV4Signer(accessKey: "AKIA", secretKey: "shh", region: "garage")  // service 기본 s3
        let auth = signer.authorization(
            method: "PUT",
            canonicalUri: "/cdn/apps/x/y.zip",
            canonicalQueryString: "",
            headers: [
                ("host", "s3.ranode.net"),
                ("x-amz-content-sha256", "deadbeef"),
                ("x-amz-date", "20260809T000000Z"),
            ],
            payloadHash: "deadbeef",
            amzDate: "20260809T000000Z",
            dateStamp: "20260809"
        )
        #expect(auth.hasPrefix("AWS4-HMAC-SHA256 Credential=AKIA/20260809/garage/s3/aws4_request"))
        #expect(auth.contains("SignedHeaders=host;x-amz-content-sha256;x-amz-date"))
        // 호출처가 헤더를 임의 순서로 줘도 정렬된다.
        #expect(auth.contains("SignedHeaders=host;x-amz-content-sha256;x-amz-date"))
    }

    @Test("헤더 입력 순서와 무관하게 정렬")
    func headersSortedRegardlessOfInputOrder() {
        let signer = SigV4Signer(accessKey: "AKIA", secretKey: "shh", region: "garage")
        let reversed = signer.authorization(
            method: "GET", canonicalUri: "/", canonicalQueryString: "",
            headers: [("x-amz-date", "20260809T000000Z"), ("host", "h"), ("x-amz-content-sha256", "p")],
            payloadHash: "p", amzDate: "20260809T000000Z", dateStamp: "20260809")
        #expect(reversed.contains("SignedHeaders=host;x-amz-content-sha256;x-amz-date"))
    }

    @Suite("canonicalQuery")
    struct CanonicalQueryTests {
        @Test("빈 쿼리는 빈 문자열")
        func empty() {
            #expect(SigV4Signer.canonicalQuery([]) == "")
        }

        @Test("이름 정렬 + unreserved 퍼센트 인코딩")
        func sortAndEncode() {
            let q = SigV4Signer.canonicalQuery([("list-type", "2"), ("prefix", "a b/c")])
            #expect(q == "list-type=2&prefix=a%20b%2Fc")
        }

        @Test("동명 키는 값으로 타이브레이크")
        func sameNameTiebreak() {
            let q = SigV4Signer.canonicalQuery([("k", "b"), ("k", "a")])
            #expect(q == "k=a&k=b")
        }
    }

    @Test("emptyPayloadHash 는 빈 문자열 SHA-256")
    func emptyPayloadHashValue() {
        #expect(SigV4Signer.emptyPayloadHash == SigV4Signer.sha256Hex(Data()))
        #expect(SigV4Signer.emptyPayloadHash == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    @Test("sha256Hex 데이터 정확")
    func sha256HexKnown() {
        #expect(SigV4Signer.sha256Hex(Data("hello".utf8)) == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    }
}
