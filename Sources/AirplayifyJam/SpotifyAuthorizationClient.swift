import AppKit
import AuthenticationServices
import Foundation

@MainActor
final class SpotifyAuthorizationClient: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.mainWindow ?? NSWindow()
    }

    func authenticate(profile: SpotifyProfile, tokenStore: SpotifyTokenStoring) async throws {
        let pkce = SpotifyPKCE()
        let state = SpotifyPKCE.makeVerifier()
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            .init(name: "client_id", value: profile.clientID), .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: "airplayifyjam://spotify/callback"),
            .init(name: "scope", value: "user-read-playback-state user-modify-playback-state"),
            .init(name: "state", value: state),
            .init(name: "code_challenge_method", value: "S256"), .init(name: "code_challenge", value: pkce.challenge)
        ]
        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let auth = ASWebAuthenticationSession(url: components.url!, callbackURLScheme: "airplayifyjam") { url, error in
                if let error { continuation.resume(throwing: error) }
                else if let url { continuation.resume(returning: url) }
                else { continuation.resume(throwing: URLError(.badServerResponse)) }
            }
            auth.presentationContextProvider = self
            session = auth
            auth.start()
        }
        guard let callbackComponents = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              let callbackState = callbackComponents.queryItems?.first(where: { $0.name == "state" })?.value,
              callbackState == state else {
            throw SpotifyAuthorizationError.stateMismatch
        }
        if let error = callbackComponents.queryItems?.first(where: { $0.name == "error" })?.value {
            throw SpotifyAuthorizationError.denied(error)
        }
        guard let code = callbackComponents.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw URLError(.userCancelledAuthentication)
        }
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents(); form.queryItems = [
            .init(name: "grant_type", value: "authorization_code"), .init(name: "code", value: code),
            .init(name: "redirect_uri", value: "airplayifyjam://spotify/callback"),
            .init(name: "client_id", value: profile.clientID), .init(name: "code_verifier", value: pkce.verifier)
        ]
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else { throw SpotifyConnectError.tokenRefreshFailed }
        let decoded = try JSONDecoder().decode(SpotifyAccessTokenResponse.self, from: data)
        guard let refreshToken = decoded.refreshToken else { throw SpotifyConnectError.missingRefreshToken }
        try tokenStore.save(SpotifyTokens(accessToken: decoded.accessToken, refreshToken: refreshToken, expiration: Date().addingTimeInterval(decoded.expiresIn)), profileID: profile.id.uuidString)
    }
}

enum SpotifyAuthorizationError: LocalizedError, Equatable {
    case stateMismatch
    case denied(String)

    var errorDescription: String? {
        switch self {
        case .stateMismatch: return "Spotify authorization could not be verified. Try again."
        case .denied(let reason): return "Spotify authorization was not granted (\(reason))."
        }
    }
}
