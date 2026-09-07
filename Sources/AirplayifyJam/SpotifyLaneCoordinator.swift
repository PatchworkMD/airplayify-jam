import Foundation
import Combine

@MainActor
final class SpotifyLaneCoordinator: ObservableObject {
    @Published private(set) var profiles: [SpotifyProfile]
    @Published private(set) var devices: [UUID: [SpotifyDevice]] = [:]
    @Published private(set) var status = "No Spotify Connect profiles"

    private let controller: SpotifyConnectController

    init() {
        self.controller = SpotifyConnectController()
        self.profiles = controller.profiles
        self.status = Self.initialStatus(for: profiles)
    }

    init(controller: SpotifyConnectController) {
        self.controller = controller
        self.profiles = controller.profiles
        self.status = Self.initialStatus(for: profiles)
    }

    func addProfile(label: String, clientID: String) {
        guard !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            try controller.add(SpotifyProfile(label: label, clientID: clientID))
            profiles = controller.profiles
            status = "Profile added. Choose Allow/Reconnect Spotify Access to authorize it."
        } catch { status = error.localizedDescription }
    }

    func refreshDevices(for profile: SpotifyProfile) {
        do {
            devices[profile.id] = try controller.refreshDevices(for: profile.id)
            status = "Devices refreshed for \(profile.label)."
        } catch { status = "\(profile.label): \(error.localizedDescription)" }
    }

    func authenticate(_ profile: SpotifyProfile) {
        status = "Opening Spotify authorization…"
        Task {
            do {
                try await controller.authenticate(profileID: profile.id)
                status = "Spotify access allowed for \(profile.label)."
            } catch { status = "\(profile.label): \(error.localizedDescription)" }
        }
    }

    func assign(device: SpotifyDevice, to profile: SpotifyProfile) {
        do {
            try controller.assign(device: device.id, to: profile.id)
            profiles = controller.profiles
            status = "Assigned \(device.name) to \(profile.label)."
        } catch { status = error.localizedDescription }
    }

    func transfer(for profile: SpotifyProfile) {
        let result: SpotifyLaneStatus
        do {
            result = try controller.transferAssignedPlayback(for: profile.id)
        } catch {
            status = "\(profile.label): \(error.localizedDescription)"
            return
        }
        switch result.kind {
        case .ready: status = "Transferred playback for \(profile.label)."
        case .missingToken: status = "\(profile.label): authenticate first."
        case .missingAssignment: status = "\(profile.label): assign a device first."
        case .accountLimitations(let message), .error(let message): status = "\(profile.label): \(message)"
        }
    }

    private static func initialStatus(for profiles: [SpotifyProfile]) -> String {
        profiles.isEmpty
            ? "No Spotify Connect profiles"
            : "\(profiles.count) Spotify Connect profile\(profiles.count == 1 ? "" : "s") ready"
    }
}
