import Foundation

struct SpotifyProfile: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var label: String
    var clientID: String
    var assignedDeviceID: String?

    init(id: UUID = UUID(), label: String, clientID: String, assignedDeviceID: String? = nil) {
        self.id = id
        self.label = label
        self.clientID = clientID
        self.assignedDeviceID = assignedDeviceID
    }
}
