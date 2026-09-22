import Foundation
import GujoCoreKit
import Testing

@testable import AppScaffoldKit

#if GujoManaged
/// 앱이 Cloud Apps 에 묻는 **세 가지**의 계약.
///
/// 앱마다 라이선스 키·활성화·오프라인 유예를 굴리지 않는다. 관심사는 셋뿐이다 —
/// ① Cloud Apps 설치 ② 연결 ③ 이 앱 사용 가능.
@Suite struct GujoManagedTests {
    // MARK: - CLI 진입점

    /// 계약 조회는 막지 않는다 — 막으면 상호운용 레지스트리가 깨지고,
    /// 무엇이 왜 막혔는지조차 읽을 수 없다.
    @Test func contractQueriesAreNeverGated() async {
        for command in ["help", "-h", "--help", "version", "-V", "--version", "capabilities"] {
            // 통과하면 그냥 반환한다(exit 하지 않는다). exit 하면 이 테스트가 죽는다.
            await GujoManaged.exitIfNotEntitled(
                arguments: [command], bundleID: "kr.gujo.demo")
            #expect(!command.isEmpty)
        }
    }

    /// 부트스트랩 면제 — 게이트를 걸면 Cloud Apps 를 깔 수단이 없어지는 둘.
    /// 목록이 조용히 늘면 구조적 의존이 이름만 남는다.
    @Test func bootstrapExemptionIsExactlyTheLedgerOwnerAndTheInstaller() {
        #expect(GujoManaged.bootstrapExemptBundleIDs == [
            "net.ranode.gujo-cloud-apps",
            "kr.gujo.gujo-cloud-apps",
            "net.ranode.appbuildmanager",
        ])
    }

    @Test func anExemptAppPassesEvenForAGatedCommand() async {
        await GujoManaged.exitIfNotEntitled(
            arguments: ["ship"], bundleID: "net.ranode.appbuildmanager")
        #expect(GujoManaged.bootstrapExemptBundleIDs.contains("net.ranode.appbuildmanager"))
    }

    @Test func statusIsAlwaysAvailableAfterLicenseRetirement() async {
        let s = await GujoManaged.status(bundleID: "kr.gujo.demo")
        #expect(s == .available)
    }

    /// CLI 는 창이 없으니 **무엇을 하면 되는지** 문장으로 줘야 한다.
    @Test func everyBlockedStatusSaysWhatToDo() {
        for s in [GujoManagedStatus.cloudAppsMissing, .notConnected, .notEntitled] {
            let m = GujoManaged.message(for: s)
            #expect(!m.isEmpty)
            #expect(m.contains("Gujo Cloud Apps"))
        }
        #expect(GujoManaged.message(for: .available).isEmpty)
    }

    @Test func statusEncodingRoundTrips() {
        for s in [GujoManagedStatus.cloudAppsMissing, .notConnected, .notEntitled, .available] {
            #expect(GujoManaged.decode(GujoManaged.encode(s)) == s)
        }
    }

    /// 판정 실패를 "권한 없음"으로 접지 않는다 — 못 물어본 것과 권한이 없는 것은 다르다.
    /// 이걸 섞으면 Cloud Apps 가 꺼져 있을 때 산 앱이 안 열린다.
    @Test func unknownIsNotTreatedAsUnentitled() {
        #expect(GujoManaged.decode("garbage") == nil)
    }

    @Test func installDetectionUsesBundleOrCLI() {
        #expect(GujoManaged.cliName == "gujo-cloud-apps")
        #expect(GujoManaged.cloudAppsBundleIDs.contains("net.ranode.gujo-cloud-apps"))
        if let path = GujoManaged.appPath {
            #expect(path.hasSuffix(".app"))
        }
    }

    @Test func currentTokenPrefersEnvironmentOverStore() {
        let env = ["GUJO_DEVICE_TOKEN": "  env-token-xyz  "]
        #expect(GujoManaged.currentToken(environment: env) == "env-token-xyz")
    }

    @Test func currentTokenReadsTokenFile() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("gujo-managed-token-\(UUID().uuidString)").path
        try "file-token-abc\n".write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let env = ["GUJO_TOKEN_FILE": path]
        #expect(GujoManaged.currentToken(environment: env) == "file-token-abc")
    }

    @Test func downloadURLResolvesDynamicallyViaEndpointRouterKit() {
        let url = GujoManaged.downloadURL
        #expect(!url.isEmpty)
        #expect(url.contains("downloads"))
    }

    @Test func lastKnownVerifiesSignedEntitlementToken() throws {
        let privKey = "+UFcGoC+42zJjLwv1wdYhKsAs3hZCdUuLqpPj7qVipY="
        let pubKey = "dyOm_RdedofBuDf38c1unku3_OE24_h6zrSzx4w5BPA"
        let bundleID = "net.ranode.scaffold-token-test"
        let now = Date()

        let token = try SignedEntitlementToken.sign(
            bundleID: bundleID,
            status: .available,
            issuedAt: now,
            privateKey: privKey
        )
        GujoManaged.storeToken(token, bundleID: bundleID)

        let resolved = GujoManaged.lastKnown(bundleID: bundleID, at: now, publicKey: pubKey)
        #expect(resolved == .available)

        // TTL 30일 초과 시 무효
        let expiredAt = now.addingTimeInterval(31 * 86400)
        let expiredResolved = GujoManaged.lastKnown(bundleID: bundleID, at: expiredAt, publicKey: pubKey)
        #expect(expiredResolved == nil)
    }
}
#endif
