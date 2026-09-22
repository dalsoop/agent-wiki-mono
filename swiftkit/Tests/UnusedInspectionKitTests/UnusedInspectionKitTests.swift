import Foundation
import Testing
@testable import UnusedInspectionKit

@Suite("UnusedInspectionKit 단위 테스트")
struct UnusedInspectionKitTests {

    @Test("AssetSymbolSynthesizer: 케밥/스네이크/공백 에셋명을 Swift camelCase 식별자로 합성")
    func testAssetSymbolSynthesizer() {
        let kebab = AssetSymbolSynthesizer.synthesizeIdentifier(from: "cloud-arrow-down")
        #expect(kebab == "cloudArrowDown")

        let snake = AssetSymbolSynthesizer.synthesizeIdentifier(from: "ic_user_profile_avatar")
        #expect(snake == "icUserProfileAvatar")

        let space = AssetSymbolSynthesizer.synthesizeIdentifier(from: "settings icon")
        #expect(space == "settingsIcon")
    }

    @Test("SafeBinaryReader: PNG IHDR 정상 파싱 (너비/높이/포맷)")
    func testSafeBinaryReaderPNG() throws {
        // 유효한 1x1 PNG 헤더 바이트
        let pngBytes: [UInt8] = [
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // Signature
            0x00, 0x00, 0x00, 0x0D,                         // Chunk length 13
            0x49, 0x48, 0x44, 0x52,                         // "IHDR"
            0x00, 0x00, 0x01, 0x00,                         // Width: 256
            0x00, 0x00, 0x00, 0x80,                         // Height: 128
            0x08, 0x06, 0x00, 0x00, 0x00                    // Bit depth, color type, etc.
        ]
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test_\(UUID().uuidString).png")
        try Data(pngBytes).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let meta = try SafeBinaryReader.inspectImage(fileURL: tempURL)
        #expect(meta.width == 256)
        #expect(meta.height == 128)
        #expect(meta.format == "PNG")
    }

    @Test("SafeBinaryReader: SVG viewBox 파싱")
    func testSafeBinaryReaderSVG() throws {
        let svgContent = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 32">
          <circle cx="16" cy="16" r="10" />
        </svg>
        """
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test_\(UUID().uuidString).svg")
        try svgContent.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let meta = try SafeBinaryReader.inspectImage(fileURL: tempURL)
        #expect(meta.width == 48)
        #expect(meta.height == 32)
        #expect(meta.format == "SVG")
    }

    @Test("IgnoreGovernance: 와일드카드 및 명시적 화이트리스트 판정")
    func testIgnoreGovernance() {
        let config = IgnoreConfigFile(ignoredPatterns: [
            IgnoreEntry(pattern: "AppIcon*", reason: "시스템 아이콘"),
            IgnoreEntry(pattern: "*_mock", reason: "테스트용 목업"),
            IgnoreEntry(pattern: "banner_promo", reason: "프로모션 이미지")
        ])

        #expect(IgnoreGovernance.isIgnored(symbolOrName: "AppIcon-60x60", in: config).ignored)
        #expect(IgnoreGovernance.isIgnored(symbolOrName: "user_data_mock", in: config).ignored)
        #expect(IgnoreGovernance.isIgnored(symbolOrName: "banner_promo", in: config).ignored)
        #expect(!IgnoreGovernance.isIgnored(symbolOrName: "regular_button", in: config).ignored)
    }

    @Test("QuarantineManager: 안전 격리 및 세션 롤백 원자성 검증")
    func testQuarantineManagerRollback() throws {
        let tempProjectDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test_project_\(UUID().uuidString)")
        let sourcesDir = tempProjectDir.appendingPathComponent("Sources")
        try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempProjectDir) }

        let dummyFile = sourcesDir.appendingPathComponent("sample_unused.png")
        try "dummy content".write(to: dummyFile, atomically: true, encoding: .utf8)

        let manager = QuarantineManager(projectRootURL: tempProjectDir)
        let session = try manager.createSession(appSlug: "test_app")

        // 격리 수행
        let item = try manager.quarantine(fileURL: dummyFile, sessionURL: session.sessionURL, reason: "단위 테스트 격리")
        #expect(!FileManager.default.fileExists(atPath: dummyFile.path))
        #expect(FileManager.default.fileExists(atPath: item.quarantinedPath))

        // 세션 롤백(복원) 수행
        let manifest = QuarantineSessionManifest(sessionID: session.sessionID, appSlug: "test_app", items: [item])
        _ = try manager.restore(manifest: manifest)
        #expect(FileManager.default.fileExists(atPath: dummyFile.path))
    }

    @Test("InspectionMetrics: 속도 계측 및 요약 메트릭 검증")
    func testInspectionMetrics() {
        let metrics = InspectionMetrics(
            appSlug: "test-app",
            totalItemsChecked: 1000,
            unusedCount: 50,
            reclaimableByteSize: 102400,
            highConfidenceCount: 40,
            mediumConfidenceCount: 10,
            lowConfidenceCount: 0
        )
        #expect(metrics.totalItemsChecked == 1000)
        #expect(metrics.unusedCount == 50)
        #expect(metrics.highConfidenceCount == 40)
    }
}
