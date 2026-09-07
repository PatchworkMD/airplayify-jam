import Foundation

struct LocalOutputSelection: Equatable, Sendable {
    let localDevices: [OutputDevice]
    let excludedDevices: [OutputDevice]

    init(devices: [OutputDevice]) {
        var local: [OutputDevice] = []
        var excluded: [OutputDevice] = []
        for device in devices {
            if Self.isSelectable(device) {
                local.append(device)
            } else {
                excluded.append(device)
            }
        }
        self.localDevices = local
        self.excludedDevices = excluded
    }

    private static func isSelectable(_ device: OutputDevice) -> Bool {
        guard device.isAvailable else { return false }
        let lower = device.name.lowercased()
        if device.kind == .airPlay || device.kind == .virtual { return false }
        if lower.contains("tutti") { return false }
        if lower.contains("multi-output device") { return false }
        if lower.contains("airplay") { return false }
        return true
    }
}
