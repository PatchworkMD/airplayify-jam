import Foundation

enum VolumeScaling {
    static func scale(_ volumes: [String: Double], fromMaster: Double, toMaster: Double) -> [String: Double] {
        guard fromMaster > 0 else { return volumes }
        let ratio = toMaster / fromMaster
        return volumes.mapValues { min(max($0 * ratio, 0), 1) }
    }
}
