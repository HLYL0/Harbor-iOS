import XCTest
@testable import HarborIOS

// MARK: - Phase 17 Trakt tests: session validity, watched threshold, ref construction.

final class TraktSessionTests: XCTestCase {

    func testSessionValidWithinThreshold() {
        let session = TraktSession(
            accessToken: "a", refreshToken: "r",
            createdAt: Date().addingTimeInterval(-10 * 86400),
            expiresIn: 7776000
        )
        // createdAt + expiresIn = 100 days from creation = 90 days from now → still within +14d threshold.
        XCTAssertTrue(session.isValid)
    }

    func testSessionInvalidPastThreshold() {
        let session = TraktSession(
            accessToken: "a", refreshToken: "r",
            createdAt: Date().addingTimeInterval(-(100 * 86400 + 14 * 86400 + 1)),
            expiresIn: 7776000
        )
        XCTAssertFalse(session.isValid)
    }

    func testDeviceCodeRoundTrip() {
        let code = TraktDeviceCode(
            deviceCode: "dc", userCode: "ABC123",
            verificationURL: "https://trakt.tv/activate",
            expiresIn: 600, interval: 5
        )
        XCTAssertEqual(code.verificationURL, TraktConfig.verifyURL)
        XCTAssertEqual(code.userCode, "ABC123")
    }

    func testWatchedMarkPercentConstant() {
        XCTAssertEqual(TraktConfig.watchedMarkPercent, 70.0)
        XCTAssertEqual(TraktConfig.stubMaxSeconds, 150.0)
    }
}
