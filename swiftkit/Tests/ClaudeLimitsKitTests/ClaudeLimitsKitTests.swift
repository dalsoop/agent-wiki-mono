import XCTest
@testable import ClaudeLimitsKit

final class ClaudeLimitsKitTests: XCTestCase {
    func testOAuthRefreshResponseParsing() throws {
        let data = Data(#"{"access_token":"new","refresh_token":"rotated","expires_in":3600}"#.utf8)
        let token = try ClaudeOAuthRefresher.parseResponse(data: data, statusCode: 200)
        XCTAssertEqual(token.accessToken, "new")
        XCTAssertEqual(token.refreshToken, "rotated")
        XCTAssertNotNil(token.expiresAt)
    }

    func testOAuthRefreshInvalidGrantClassification() {
        let data = Data(#"{"error":"invalid_grant"}"#.utf8)
        XCTAssertThrowsError(try ClaudeOAuthRefresher.parseResponse(data: data, statusCode: 400)) { error in
            guard case ClaudeOAuthRefreshError.invalidGrant = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    private func limits(five: Double, seven: Double) -> ServerLimits {
        ServerLimits(
            fiveHourUtilization: five,
            fiveHourReset: Date(timeIntervalSince1970: 0),
            sevenDayUtilization: seven,
            sevenDayReset: Date(timeIntervalSince1970: 0),
            status: "allowed",
            fetchedAt: Date(timeIntervalSince1970: 0)
        )
    }

    func testMaxUtilizationTakesBusierWindow() {
        XCTAssertEqual(limits(five: 0.3, seven: 0.72).maxUtilization, 0.72, accuracy: 1e-9)
        XCTAssertEqual(limits(five: 0.9, seven: 0.1).maxUtilization, 0.9, accuracy: 1e-9)
    }

    func testHeadroomIsComplementOfMaxUtilization() {
        XCTAssertEqual(limits(five: 0.2, seven: 0.8).headroomPercent, 20)
        XCTAssertEqual(limits(five: 0.0, seven: 0.0).headroomPercent, 100)
    }

    func testHeadroomClampsAtZeroWhenOverLimit() {
        XCTAssertEqual(limits(five: 1.2, seven: 0.5).headroomPercent, 0)
    }
}
