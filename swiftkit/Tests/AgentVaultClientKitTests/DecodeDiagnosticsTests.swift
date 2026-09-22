import XCTest
@testable import AgentVaultClientKit

/// 디코드 실패 문장은 **다음에 뭘 할지**를 알려줘야 한다.
///
/// 2026-08-10 실사고: 낡은 설치본 때문에 모델이 어긋나 vault list 가 죽었는데,
/// 메시지가 "The data couldn't be read…" 뿐이라 파이프·권한·볼트 잠금을 헛짚었다.
final class DecodeDiagnosticsTests: XCTestCase {
    private struct Sample: Decodable {
        let id: String
        let count: Int
    }

    func testMissingKeyNamesTheKeyAndSuggestsReinstall() {
        let output = #"{"id":"a"}"#
        let error = decodeFailure(Sample.self, from: output)
        let message = AgentVaultCLIClient.diagnose(error, output: output)
        XCTAssertTrue(message.contains("count"), message)
        XCTAssertTrue(message.contains("app-build-manager install"), message)
    }

    func testTypeMismatchNamesThePath() {
        let output = #"{"id":"a","count":"열"}"#
        let error = decodeFailure(Sample.self, from: output)
        let message = AgentVaultCLIClient.diagnose(error, output: output)
        XCTAssertTrue(message.contains("count"), message)
    }

    /// JSON 이 아예 아니면 재설치가 아니라 **그 출력 자체**를 보여줘야 한다.
    func testNonJSONOutputIsQuotedInsteadOfBlamingTheModel() {
        let output = "알 수 없는 명령: card"
        let error = decodeFailure(Sample.self, from: output)
        let message = AgentVaultCLIClient.diagnose(error, output: output)
        XCTAssertTrue(message.contains("알 수 없는 명령"), message)
        XCTAssertFalse(message.contains("app-build-manager"), message)
    }

    func testEmptyOutputSaysSo() {
        let error = decodeFailure(Sample.self, from: "")
        XCTAssertTrue(AgentVaultCLIClient.diagnose(error, output: "  \n").contains("빈 응답"))
    }

    private func decodeFailure<T: Decodable>(_ type: T.Type, from output: String) -> Error {
        do {
            _ = try JSONDecoder().decode(type, from: Data(output.utf8))
            XCTFail("표본이 디코드에 성공했다 — 테스트 전제가 깨졌다")
            return NSError(domain: "test", code: 0)
        } catch {
            return error
        }
    }
}
