import XCTest
import Combine
@testable import StateMirrorKit

final class StateMirrorAutoTests: XCTestCase {
    /// @Observable 계열(직접 저장 프로퍼티)을 흉내낸 평범한 클래스.
    final class PlainModel {
        var title = "hi"
        var count = 3
        var busy = false
        var ratio = 0.5
        var items = [1, 2, 3]
        var url = URL(string: "https://x.test")!
        var mode: Mode = .running
        var optionalName: String? = "n"
        var nilName: String? = nil
        var closure: () -> Void = {}   // 직렬화 불가 → 생략돼야 함
        var nested: Nested? = Nested(repoRoot: "/x", count: 9)   // 복합 struct → 통째 생략(첫 스칼라 오추출 금지)
        enum Mode { case idle, running }
        struct Nested { var repoRoot: String; var count: Int }
    }

    func testReflectSummaryExtractsScalars() {
        let s = StateMirror.reflectSummary(PlainModel())
        XCTAssertEqual(s["title"] as? String, "hi")
        XCTAssertEqual(s["count"] as? Int, 3)
        XCTAssertEqual(s["busy"] as? Bool, false)
        XCTAssertEqual(s["ratio"] as? Double, 0.5)
        XCTAssertEqual(s["items"] as? Int, 3)                 // 컬렉션 → 원소 수
        XCTAssertEqual(s["url"] as? String, "https://x.test")
        XCTAssertEqual(s["mode"] as? String, "running")       // enum → case 이름
        XCTAssertEqual(s["optionalName"] as? String, "n")     // Optional 언랩
        XCTAssertNil(s["nilName"])                            // nil 은 생략
        XCTAssertNil(s["closure"])                            // 직렬화 불가 생략
        XCTAssertNil(s["nested"])                             // 복합 struct 통째 생략(내부 스칼라 오추출 금지)
    }

    /// ObservableObject + @Published 언랩 확인.
    final class PublishedModel: ObservableObject {
        @Published var name = "pub"
        @Published var n = 7
        @Published var on = true
    }

    func testReflectSummaryUnwrapsPublished() {
        let s = StateMirror.reflectSummary(PublishedModel())
        XCTAssertEqual(s["name"] as? String, "pub")
        XCTAssertEqual(s["n"] as? Int, 7)
        XCTAssertEqual(s["on"] as? Bool, true)
    }

    func testAutoPublishWritesFile() throws {
        let app = "AutoMirrorTest-\(UUID().uuidString.prefix(8))"
        StateMirror.autoPublish(app: app, reflecting: PlainModel())
        defer { StateMirror.clear(app: app) }
        let data = try Data(contentsOf: URL(fileURLWithPath: StateMirror.path(app: app)))
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(obj["app"] as? String, app)
        let state = obj["state"] as! [String: Any]
        XCTAssertEqual(state["title"] as? String, "hi")
    }
}
