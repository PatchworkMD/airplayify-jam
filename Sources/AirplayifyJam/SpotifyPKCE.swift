import Foundation
import CryptoKit

struct SpotifyPKCE: Sendable, Equatable {
    let verifier: String
    let challenge: String

    init(verifier: String? = nil) {
        let generatedVerifier = verifier ?? SpotifyPKCE.makeVerifier()
        self.verifier = generatedVerifier
        self.challenge = SpotifyPKCE.challenge(for: generatedVerifier)
    }

    static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).spotifyBase64URLString()
    }

    static func makeVerifier(length: Int = 64) -> String {
        precondition((43...128).contains(length), "PKCE verifier length must be 43...128")
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return String((0..<length).compactMap { _ in alphabet.randomElement() })
    }
}

private extension Data {
    func spotifyBase64URLString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
