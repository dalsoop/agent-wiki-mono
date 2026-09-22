import Testing
import Foundation
@testable import StoreAssetKit

/// 표지 렌더 계약 — 파라미터만으로 PNG 가 나오고 지오메트리 계약을 지킨다.
struct StoreCoverRendererTests {

    @Test func 표지를_렌더하면_PNG_파일이_생긴다() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("StoreAssetKit-\(UUID().uuidString)", isDirectory: true)
        let url = try StoreCoverRenderer.render(
            slug: "probe-skill",
            title: "초록 배경 누끼 처리 스킬",
            tagline: "AI 에이전트와 결합해 작업을 자동화합니다",
            directory: dir,
            variant: 1
        )
        #expect(FileManager.default.fileExists(atPath: url.path))
        let data = try Data(contentsOf: url)
        #expect(data.count > 10_000)
        // PNG 시그니처
        #expect([UInt8](data.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
        // variant 가 파일명에 반영된다
        let second = try StoreCoverRenderer.render(
            slug: "probe-skill", title: "T", tagline: "", directory: dir, variant: 2
        )
        #expect(second.lastPathComponent == "probe-skill-2.png")
    }
}
