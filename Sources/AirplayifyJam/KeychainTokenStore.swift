import Foundation
import Security

struct SpotifyTokens: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiration: Date

    var isExpired: Bool { expiration <= Date() }
}

protocol SpotifyTokenStoring: Sendable {
    func load(profileID: String) throws -> SpotifyTokens?
    func save(_ tokens: SpotifyTokens, profileID: String) throws
    func remove(profileID: String) throws
}

enum KeychainTokenStoreError: Error, Equatable {
    case unexpectedStatus(OSStatus)
    case encodingFailed
    case decodingFailed
}

final class KeychainTokenStore: SpotifyTokenStoring, @unchecked Sendable {
    static let service = "com.austinwise.airplayifyjam.spotify"

    private let service: String
    private let encoder: PropertyListEncoder
    private let decoder: PropertyListDecoder

    init(service: String = KeychainTokenStore.service) {
        self.service = service
        self.encoder = PropertyListEncoder()
        self.encoder.outputFormat = .binary
        self.decoder = PropertyListDecoder()
    }

    func load(profileID: String) throws -> SpotifyTokens? {
        var result: CFTypeRef?
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: profileID,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainTokenStoreError.unexpectedStatus(status) }
        guard let data = result as? Data else { throw KeychainTokenStoreError.decodingFailed }
        return try decoder.decode(SpotifyTokens.self, from: data)
    }

    func save(_ tokens: SpotifyTokens, profileID: String) throws {
        let data: Data
        do {
            data = try encoder.encode(tokens)
        } catch {
            throw KeychainTokenStoreError.encodingFailed
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: profileID
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let addQuery = query.merging(attributes) { _, new in new }
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainTokenStoreError.unexpectedStatus(addStatus) }
            return
        }
        guard status == errSecSuccess else { throw KeychainTokenStoreError.unexpectedStatus(status) }
    }

    func remove(profileID: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: profileID
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainTokenStoreError.unexpectedStatus(status)
        }
    }
}
