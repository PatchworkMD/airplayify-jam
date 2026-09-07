import XCTest
@testable import AirplayifyJam

final class SpotifyPKCETests: XCTestCase {
    func testRFC7636ChallengeMatchesKnownVector() {
        let pkce = SpotifyPKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        XCTAssertEqual(pkce.challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testGeneratedVerifierUsesAllowedCharactersAndLength() {
        let pkce = SpotifyPKCE()
        XCTAssertEqual(pkce.verifier.count, 64)
        XCTAssertTrue(pkce.verifier.allSatisfy { "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~".contains($0) })
        XCTAssertFalse(pkce.challenge.contains("="))
    }
}
