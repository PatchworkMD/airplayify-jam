import Foundation

struct PartyOutputPlan: Equatable, Sendable {
    let localDevices: [OutputDevice]
    let airPlayNames: [String]
    let unavailableDevices: [OutputDevice]

    init(group: OutputGroup, liveDevices: [OutputDevice]) {
        let liveByID = Dictionary(uniqueKeysWithValues: liveDevices.map { ($0.id, $0) })
        var local: [OutputDevice] = []
        var airPlay: [String] = []
        var unavailable: [OutputDevice] = []

        for id in group.deviceIDs {
            guard let device = liveByID[id] else {
                unavailable.append(OutputDevice(id: id, name: group.deviceNames[id] ?? id, kind: .unknown, isAvailable: false))
                continue
            }
            guard device.isAvailable else {
                unavailable.append(device)
                continue
            }
            guard Self.isSelectable(device) else { continue }
            switch device.kind {
            case .airPlay:
                if !Self.isMacBookReceiver(device) {
                    airPlay.append(device.name)
                }
            case .virtual:
                continue
            default:
                local.append(device)
            }
        }

        self.localDevices = local
        self.airPlayNames = airPlay
        self.unavailableDevices = unavailable
    }

    private static func isSelectable(_ device: OutputDevice) -> Bool {
        guard device.isAvailable else { return false }
        if device.kind == .virtual { return false }
        if DeviceRegistry.isInternal(device) { return false }
        return true
    }

    private static func isMacBookReceiver(_ device: OutputDevice) -> Bool {
        device.kind == .airPlay && device.name.lowercased().contains("macbook")
    }
}
