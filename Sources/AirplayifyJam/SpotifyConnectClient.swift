import Foundation

protocol SpotifyHTTPTransport: Sendable {
    func request(_ request: URLRequest) throws -> (Data, HTTPURLResponse)
}

struct URLSessionSpotifyTransport: SpotifyHTTPTransport {
    func request(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<(Data, HTTPURLResponse), Error>!
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                result = .failure(error)
            } else if let response = response as? HTTPURLResponse {
                result = .success((data ?? Data(), response))
            } else {
                result = .failure(URLError(.badServerResponse))
            }
            semaphore.signal()
        }.resume()
        semaphore.wait()
        return try result.get()
    }
}

final class SpotifyConnectClient {
    private let profile: SpotifyProfile
    private let tokenStore: SpotifyTokenStoring
    private let transport: SpotifyHTTPTransport
    private let baseURL = URL(string: "https://api.spotify.com/v1")!
    private let authURL = URL(string: "https://accounts.spotify.com/api/token")!

    init(
        profile: SpotifyProfile,
        tokenStore: SpotifyTokenStoring = KeychainTokenStore(),
        transport: SpotifyHTTPTransport = URLSessionSpotifyTransport()
    ) {
        self.profile = profile
        self.tokenStore = tokenStore
        self.transport = transport
    }

    func devices() throws -> [SpotifyDevice] {
        let response = try performAuthorizedRequest(path: "me/player/devices", method: "GET", body: nil, retryOnUnauthorized: true)
        return try JSONDecoder().decode(SpotifyDeviceResponse.self, from: response.data).devices
    }

    func transfer(to deviceID: String, play: Bool = true) throws {
        _ = try performAuthorizedRequest(
            path: "me/player",
            method: "PUT",
            body: try JSONSerialization.data(withJSONObject: [
                "device_ids": [deviceID],
                "play": play
            ]),
            contentType: "application/json",
            retryOnUnauthorized: true,
            expectedStatusCode: 204
        )
    }

    private func performAuthorizedRequest(
        path: String,
        method: String,
        body: Data?,
        contentType: String? = nil,
        retryOnUnauthorized: Bool,
        expectedStatusCode: Int = 200
    ) throws -> (data: Data, response: HTTPURLResponse) {
        let token = try loadValidToken()
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        request.httpBody = body

        let (data, response) = try transport.request(request)
        if response.statusCode == 401, retryOnUnauthorized, let refreshed = try refreshTokenIfNeeded(current: token) {
            var retryRequest = request
            retryRequest.setValue("Bearer \(refreshed.accessToken)", forHTTPHeaderField: "Authorization")
            let (retryData, retryResponse) = try transport.request(retryRequest)
            guard retryResponse.statusCode == expectedStatusCode else {
                throw SpotifyConnectError.invalidResponse(retryResponse.statusCode, Self.redactedBody(retryData))
            }
            return (retryData, retryResponse)
        }
        guard response.statusCode == expectedStatusCode else {
            throw SpotifyConnectError.invalidResponse(response.statusCode, Self.redactedBody(data))
        }
        return (data, response)
    }

    private func loadValidToken() throws -> SpotifyTokens {
        guard let token = try tokenStore.load(profileID: profile.id.uuidString) else {
            throw SpotifyConnectError.missingToken
        }
        if token.expiration <= Date().addingTimeInterval(60) {
            return try refreshTokenIfNeeded(current: token) ?? token
        }
        return token
    }

    private func refreshTokenIfNeeded(current: SpotifyTokens) throws -> SpotifyTokens? {
        let refreshed = try refreshAccessToken(refreshToken: current.refreshToken)
        try tokenStore.save(refreshed, profileID: profile.id.uuidString)
        return refreshed
    }

    private func refreshAccessToken(refreshToken: String) throws -> SpotifyTokens {
        guard !profile.clientID.isEmpty else { throw SpotifyConnectError.missingRefreshToken }

        var request = URLRequest(url: authURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "client_id", value: profile.clientID)
        ]
        var components = URLComponents()
        components.queryItems = body
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try transport.request(request)
        guard response.statusCode == 200 else {
            throw SpotifyConnectError.tokenRefreshFailed
        }
        let decoded = try JSONDecoder().decode(SpotifyAccessTokenResponse.self, from: data)
        let newRefreshToken = decoded.refreshToken ?? refreshToken
        return SpotifyTokens(
            accessToken: decoded.accessToken,
            refreshToken: newRefreshToken,
            expiration: Date().addingTimeInterval(decoded.expiresIn)
        )
    }

    private static func redactedBody(_ data: Data) -> String {
        let body = String(data: data, encoding: .utf8) ?? ""
        return body.replacingOccurrences(of: "(?i)(bearer\\s+|access_token\\\"?\\s*[:=]\\s*\\\"?)[^\\\"\\s,}]+", with: "$1[REDACTED]", options: .regularExpression)
    }
}
