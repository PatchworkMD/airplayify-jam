import Foundation

struct OutputDevice: Identifiable, Codable, Equatable, Sendable {
    enum Kind: String, Codable { case airPlay, hdmi, usb, builtIn, virtual, unknown }
    let id: String
    let name: String
    let kind: Kind
    var isAvailable: Bool = true
    var isMuted: Bool = false
}

struct OutputGroup: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var deviceIDs: [String]
    var deviceNames: [String: String] = [:]
}
