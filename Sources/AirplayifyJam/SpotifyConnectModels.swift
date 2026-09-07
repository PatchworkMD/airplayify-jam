import Foundation

struct SpotifyDevice: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let type: String
    let isActive: Bool
    let isPrivateSession: Bool
    let isRestricted: Bool
    let volumePercent: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, type
        case isActive = "is_active"
        case isPrivateSession = "is_private_session"
        case isRestricted = "is_restricted"
        case volumePercent = "volume_percent"
    }
}

struct SpotifyDeviceResponse: Codable, Sendable {
    let devices: [SpotifyDevice]
}

struct SpotifyAccessTokenResponse: Codable, Sendable {
    let accessToken: String
    let tokenType: String
    let scope: String?
    let expiresIn: TimeInterval
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case scope
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }
}

enum SpotifyConnectError: Error, Equatable {
    case invalidResponse(Int, String)
    case missingToken
    case missingRefreshToken
    case tokenRefreshFailed
}

extension SpotifyConnectError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidResponse(let status, _): return "Spotify returned HTTP \(status)."
        case .missingToken: return "Authenticate this Spotify profile first."
        case .missingRefreshToken: return "This Spotify profile has no refresh token."
        case .tokenRefreshFailed: return "Spotify token refresh failed. Authenticate again."
        }
    }
}
