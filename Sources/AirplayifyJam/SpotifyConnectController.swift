import Foundation

struct SpotifyLaneStatus: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case ready, missingToken, missingAssignment, accountLimitations(String), error(String) }
    let profileID: UUID
    let kind: Kind
}

final class SpotifyConnectController {
    private(set) var profiles: [SpotifyProfile]
    let store: SpotifyLaneStore
    let tokenStore: SpotifyTokenStoring
    let transport: SpotifyHTTPTransport

    init(
        store: SpotifyLaneStore = SpotifyLaneStore(),
        tokenStore: SpotifyTokenStoring = KeychainTokenStore(),
        transport: SpotifyHTTPTransport = URLSessionSpotifyTransport()
    ) {
        self.store = store
        self.tokenStore = tokenStore
        self.transport = transport
        self.profiles = store.load()
    }

    func add(_ profile: SpotifyProfile) throws {
        profiles.append(profile)
        try store.save(profiles)
    }

    func remove(_ id: UUID) throws {
        profiles.removeAll { $0.id == id }
        try store.save(profiles)
    }

    func assign(device: String, to id: UUID) throws {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].assignedDeviceID = device
        try store.save(profiles)
    }

    func refreshDevices(for profileID: UUID) throws -> [SpotifyDevice] {
        guard let profile = profiles.first(where: { $0.id == profileID }) else {
            return []
        }
        return try SpotifyConnectClient(profile: profile, tokenStore: tokenStore, transport: transport).devices()
    }

    @MainActor
    func authenticate(profileID: UUID) async throws {
        guard let profile = profiles.first(where: { $0.id == profileID }) else { return }
        try await SpotifyAuthorizationClient().authenticate(profile: profile, tokenStore: tokenStore)
    }

    func transferAssignedPlayback(for profileID: UUID) throws -> SpotifyLaneStatus {
        guard let profile = profiles.first(where: { $0.id == profileID }) else {
            return SpotifyLaneStatus(profileID: profileID, kind: .error("Unknown profile"))
        }
        guard let assignedDeviceID = profile.assignedDeviceID, !assignedDeviceID.isEmpty else {
            return SpotifyLaneStatus(profileID: profileID, kind: .missingAssignment)
        }
        guard (try? tokenStore.load(profileID: profile.id.uuidString)) != nil else {
            return SpotifyLaneStatus(profileID: profileID, kind: .missingToken)
        }
        do {
            try SpotifyConnectClient(profile: profile, tokenStore: tokenStore, transport: transport).transfer(to: assignedDeviceID)
            return SpotifyLaneStatus(profileID: profileID, kind: .ready)
        } catch SpotifyConnectError.invalidResponse(let code, _) where code == 403 {
            return SpotifyLaneStatus(profileID: profileID, kind: .accountLimitations("Spotify plan or device restrictions blocked the transfer"))
        } catch {
            return SpotifyLaneStatus(profileID: profileID, kind: .error(String(describing: error)))
        }
    }
}
