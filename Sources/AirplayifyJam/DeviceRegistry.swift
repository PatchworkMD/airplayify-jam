import Foundation

enum DeviceRegistry {
    static func isInternal(_ device: OutputDevice) -> Bool {
        let lower = device.name.lowercased()
        return lower.contains("airplayify")
            || lower.contains("tutti")
            || lower == "airplay"
            || lower.contains("blackhole")
            || lower.contains("multi-output device")
            || lower.contains("aggregate device")
    }

    static func isSelfAirPlay(_ device: OutputDevice) -> Bool {
        let lower = device.name.lowercased()
        return device.kind == .airPlay && lower.contains("macbook")
    }

    static func displayable(_ devices: [OutputDevice]) -> [OutputDevice] {
        var seen = Set<String>()
        var result: [OutputDevice] = []
        for device in devices where !isInternal(device) && !isSelfAirPlay(device) {
            let key = device.name
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard seen.insert(key).inserted else { continue }
            result.append(device)
        }
        return result
    }

    static func groupable(_ devices: [OutputDevice]) -> [OutputDevice] {
        devices.filter { device in
            if !device.isAvailable { return false }
            if device.kind == .virtual { return false }
            if isInternal(device) { return false }
            if isSelfAirPlay(device) { return false }
            return true
        }
    }

    static func reconcile(live: [OutputDevice], groups: [OutputGroup]) -> [OutputDevice] {
        var result = live
        let knownIDs = Set(live.map(\.id))
        for group in groups {
            for id in group.deviceIDs where !knownIDs.contains(id) {
                let name = group.deviceNames[id] ?? id
                result.append(OutputDevice(id: id, name: name, kind: .unknown, isAvailable: false))
            }
        }
        return result
    }

    static func rebind(_ group: OutputGroup, to liveDevices: [OutputDevice]) -> OutputGroup {
        let liveByID = Dictionary(uniqueKeysWithValues: liveDevices.map { ($0.id, $0) })
        let liveByName = Dictionary(
            liveDevices.map { (normalizedName($0.name), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var reboundIDs: [String] = []
        var reboundNames: [String: String] = [:]
        var seen = Set<String>()

        for savedID in group.deviceIDs {
            let savedName = group.deviceNames[savedID] ?? savedID
            let live = liveByID[savedID] ?? liveByName[normalizedName(savedName)]
            let targetID = live?.id ?? savedID
            guard seen.insert(targetID).inserted else { continue }
            reboundIDs.append(targetID)
            reboundNames[targetID] = live?.name ?? savedName
        }

        var rebound = group
        rebound.deviceIDs = reboundIDs
        rebound.deviceNames = reboundNames
        return rebound
    }

    static func makeEverywhere(from devices: [OutputDevice]) -> OutputGroup {
        let selected = groupable(devices)
        return OutputGroup(
            id: UUID(),
            name: "Everywhere",
            deviceIDs: selected.map(\.id),
            deviceNames: Dictionary(uniqueKeysWithValues: selected.map { ($0.id, $0.name) }))
    }

    static func sanitize(_ group: OutputGroup) -> OutputGroup {
        let keep = group.deviceIDs.filter { id in
            let name = group.deviceNames[id] ?? id
            if id.hasPrefix("airplay:") && name.contains("macbook") { return false }
            return !isInternal(OutputDevice(id: id, name: name, kind: .unknown))
        }
        var result = group
        result.deviceIDs = keep
        result.deviceNames = group.deviceNames.filter { keep.contains($0.key) }
        return result
    }

    private static func normalizedName(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .lowercased()
    }
}
