import Foundation

@main
struct LocalRouteProbe {
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let includeVirtualAudioLoopback = arguments.contains("--include-blackhole")
        let requestedNames = arguments.filter { $0 != "--include-blackhole" }
        let available = AudioDeviceCatalog.devices()
        let selected = available.filter { device in
            requestedNames.contains { $0.caseInsensitiveCompare(device.name) == .orderedSame }
        }

        guard selected.count == requestedNames.count else {
            let found = Set(selected.map(\.name))
            let missing = requestedNames.filter { !found.contains($0) }
            throw NSError(
                domain: "AirplayifyJam.LocalRouteProbe",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Local outputs not found: \(missing.joined(separator: ", "))"]
            )
        }

        let manager = LocalOutputGroupManager()
        try manager.activate(selected, includeVirtualAudioLoopback: includeVirtualAudioLoopback)
        print("route=active aggregate=\(manager.activeDeviceID ?? 0) local=\(selected.map(\.name).joined(separator: ",")) blackhole=\(includeVirtualAudioLoopback ? "yes" : "no")")
        fflush(stdout)
        Thread.sleep(forTimeInterval: 12)
        manager.deactivate()
        print("route=restored")
    }
}
