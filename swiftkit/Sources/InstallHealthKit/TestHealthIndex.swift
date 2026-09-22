import Foundation
import StateRootKit

/// "이 함대의 테스트가 **컴파일이라도 되나**" 를 파일 한 번 읽어 답하는 색인.
///
/// ## 왜 필요한가
///
/// 실측 2026-08-11: `business-people` 테스트가 개명 리팩터(299c08ca) 이후 몇 주째
/// `cannot find 'LedgerCLIKit'` 로 **컴파일조차 안 되는 채** 머지돼 있었다. 그런데
/// 모든 파이프라인이 green 이었고 `doctor` 도 ✓ 를 줬다. 세 겹으로 못 봤다:
///
/// 1. `macos:unit-tests` 는 MR 에서 안 돈다(main push·web·schedule 전용 — 워크스테이션이
///    꺼져 있을 때 머지를 막지 않으려는 의도적 설계).
/// 2. 야간 전수 스윕은 `swift build` 만 한다 — `--build-tests` 가 없어 테스트 타깃을
///    아예 컴파일하지 않는다.
/// 3. `doctor` 에는 테스트 축이 없다(계약·이름·설치본만 센다).
///
/// 2026-07-27 에도 같은 형태를 밟았다 — 전수 빌드해 보니 22개가 컴파일 불가인데 파이프라인은
/// 전부 green 이었다. 그때 만든 게 빌드 스윕이고, 이건 그 테스트 판이다.
///
/// ## 왜 색인인가
///
/// 전수 `swift build --build-tests` 는 1~2시간이 걸린다. `doctor` 가 매번 할 일이 아니다.
/// 이미 그 계산을 하는 곳(야간 스윕)이 결과를 여기 적고, `doctor` 는 이 파일만 읽는다.
/// `StaleInstallIndex` 와 같은 구조다.
///
/// ## 측정 안 된 상태를 ✓ 로 내지 않는다
///
/// 색인이 없으면 "이상 없음" 이 아니라 **"측정 안 됨"** 이다. 지금까지 못 잡은 이유가
/// 정확히 그거다 — 아무도 재지 않은 축이 조용히 통과로 세어졌다.
public enum TestHealthIndex: Sendable {
    public static var indexURL: URL {
        StateRootKit.url(".agent-ops/test-health/index.json")
    }

    public struct BrokenApp: Codable, Sendable, Equatable {
        public let app: String
        /// 첫 컴파일 오류 한 줄 — 고치러 갈 실마리.
        public let error: String

        public init(app: String, error: String) {
            self.app = app
            self.error = error
        }
    }

    public struct Snapshot: Codable, Sendable, Equatable {
        public let updatedAt: String
        /// 테스트 타깃 컴파일에 성공한 앱 수.
        public let ok: Int
        /// 테스트 디렉터리가 아예 없는 앱 수 — 깨진 것과 구분한다.
        public let withoutTests: Int
        public let broken: [BrokenApp]

        public init(updatedAt: String, ok: Int, withoutTests: Int, broken: [BrokenApp]) {
            self.updatedAt = updatedAt
            self.ok = ok
            self.withoutTests = withoutTests
            self.broken = broken
        }
    }

    public static func write(
        ok: Int, withoutTests: Int, broken: [BrokenApp],
        at url: URL = indexURL, now: Date = Date()
    ) {
        let snapshot = Snapshot(
            updatedAt: ISO8601DateFormatter().string(from: now),
            ok: ok, withoutTests: withoutTests, broken: broken)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        do { try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true) } catch { _ = error }
        do { try data.write(to: url, options: .atomic) } catch { _ = error }
    }

    public static func read(at url: URL = indexURL) -> Snapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    /// 색인이 얼마나 오래됐나. 스윕이 안 돌면 이 값이 계속 커진다 — 그것도 신호다.
    public static func ageInDays(of snapshot: Snapshot, now: Date = Date()) -> Int? {
        guard let updated = ISO8601DateFormatter().date(from: snapshot.updatedAt) else { return nil }
        return Calendar(identifier: .gregorian)
            .dateComponents([.day], from: updated, to: now).day
    }
}
