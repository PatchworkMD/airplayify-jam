import XCTest
@testable import AirplayifyJam

final class SpotifyConnectClientTests: XCTestCase {
    func testDevicesDecodeFromFixture() throws {
        let transport = FakeSpotifyTransport(
            responses: [
                .init(statusCode: 200, body: #"{"devices":[{"id":"abc","name":"Living Room","type":"Speaker","is_active":false,"is_private_session":false,"is_restricted":false,"volume_percent":55}]}"#.data(using: .utf8)!)
            ]
        )
        let tokenStore = InMemoryTokenStore(tokens: SpotifyTokens(accessToken: "token", refreshToken: "refresh", expiration: .distantFuture))
        let client = SpotifyConnectClient(profile: makeProfile(), tokenStore: tokenStore, transport: transport)

        let devices = try client.devices()

        XCTAssertEqual(devices.map(\.name), ["Living Room"])
        XCTAssertEqual(transport.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer token")
    }

    func testTransferUses204Success() throws {
        let transport = FakeSpotifyTransport(
            responses: [
                .init(statusCode: 204, body: Data())
            ]
        )
        let tokenStore = InMemoryTokenStore(tokens: SpotifyTokens(accessToken: "token", refreshToken: "refresh", expiration: .distantFuture))
        let client = SpotifyConnectClient(profile: makeProfile(), tokenStore: tokenStore, transport: transport)

        try client.transfer(to: "device-1")

        XCTAssertEqual(transport.requests.last?.httpMethod, "PUT")
        XCTAssertTrue(String(data: transport.requests.last?.httpBody ?? Data(), encoding: .utf8)?.contains("\"play\":true") ?? false)
    }

    func testExpiredTokenRefreshesAndRetriesAfterUnauthorized() throws {
        let transport = FakeSpotifyTransport(
            responses: [
                .init(statusCode: 200, body: #"{"access_token":"fresh","token_type":"Bearer","expires_in":3600,"refresh_token":"new-refresh"}"#.data(using: .utf8)!),
                .init(statusCode: 200, body: #"{"devices":[]}"#.data(using: .utf8)!)
            ]
        )
        let tokenStore = InMemoryTokenStore(tokens: SpotifyTokens(accessToken: "expired", refreshToken: "refresh", expiration: Date(timeIntervalSinceNow: -10)))
        let profile = makeProfile()
        let client = SpotifyConnectClient(profile: profile, tokenStore: tokenStore, transport: transport)

        let devices = try client.devices()

        XCTAssertTrue(devices.isEmpty)
        XCTAssertEqual(tokenStore.savedTokens?.accessToken, "fresh")
        XCTAssertEqual(transport.requests[0].url?.absoluteString, "https://accounts.spotify.com/api/token")
        XCTAssertEqual(transport.requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer fresh")
    }

    func testAPIErrorDoesNotExposeBearerToken() {
        let secret = ["Bearer", "super-secret-token"].joined(separator: " ")
        let transport = FakeSpotifyTransport(responses: [.init(statusCode: 403, body: Data(secret.utf8))])
        let store = InMemoryTokenStore(tokens: SpotifyTokens(accessToken: "token", refreshToken: "refresh", expiration: .distantFuture))
        XCTAssertThrowsError(try SpotifyConnectClient(profile: makeProfile(), tokenStore: store, transport: transport).devices()) { error in
            XCTAssertFalse(String(describing: error).contains("super-secret-token"))
        }
    }

    func testAPIErrorSurfacesStatusAndBody() {
        let transport = FakeSpotifyTransport(
            responses: [
                .init(statusCode: 403, body: #"{"error":"forbidden"}"#.data(using: .utf8)!)
            ]
        )
        let tokenStore = InMemoryTokenStore(tokens: SpotifyTokens(accessToken: "token", refreshToken: "refresh", expiration: .distantFuture))
        let client = SpotifyConnectClient(profile: makeProfile(), tokenStore: tokenStore, transport: transport)

        XCTAssertThrowsError(try client.devices()) { error in
            guard case SpotifyConnectError.invalidResponse(let status, let body) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(status, 403)
            XCTAssertTrue(body.contains("forbidden"))
        }
    }

    private func makeProfile() -> SpotifyProfile {
        SpotifyProfile(id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!, label: "Primary", clientID: "client-id")
    }
}

private struct FakeSpotifyResponse {
    let statusCode: Int
    let body: Data
}

private final class FakeSpotifyTransport: SpotifyHTTPTransport, @unchecked Sendable {
    private var queuedResponses: [FakeSpotifyResponse]
    private(set) var requests: [URLRequest] = []

    init(responses: [FakeSpotifyResponse]) {
        self.queuedResponses = responses
    }

    func request(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        precondition(!queuedResponses.isEmpty, "Missing fixture response")
        let next = queuedResponses.removeFirst()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: next.statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (next.body, response)
    }
}

private final class InMemoryTokenStore: SpotifyTokenStoring, @unchecked Sendable {
    var tokens: SpotifyTokens?
    private(set) var savedTokens: SpotifyTokens?

    init(tokens: SpotifyTokens?) {
        self.tokens = tokens
    }

    func load(profileID: String) throws -> SpotifyTokens? { tokens }
    func save(_ tokens: SpotifyTokens, profileID: String) throws { self.tokens = tokens; self.savedTokens = tokens }
    func remove(profileID: String) throws { tokens = nil }
}
