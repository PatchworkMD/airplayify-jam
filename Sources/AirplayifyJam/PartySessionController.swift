import Foundation
import Combine

@MainActor
protocol LocalOutputActivating {
    func activate(_ devices: [OutputDevice], includeVirtualAudioLoopback: Bool) throws
    func deactivate()
}

@MainActor
protocol AirPlayBridging {
    var isRunning: Bool { get }
    var isReady: Bool { get }
    var status: String { get }
    var requiresVirtualAudioRoute: Bool { get }
    func start(deviceNames: [String]) -> Result<Void, BridgeLaunchError>
    func refreshStatus()
    func stop()
}

@MainActor
final class PartySessionController: ObservableObject {
    typealias State = PartyRuntime.State

    @Published private(set) var state: State
    @Published private(set) var lastPlan: PartyOutputPlan?
    private let runtime: PartyRuntime

    init(localOutputs: LocalOutputActivating, bridge: AirPlayBridging) {
        let runtime = PartyRuntime(localOutputs: localOutputs, bridge: bridge)
        self.runtime = runtime
        self.state = runtime.state
        self.lastPlan = runtime.lastPlan
    }

    func start(plan: PartyOutputPlan) {
        runtime.start(plan: plan)
        syncFromRuntime()
    }

    func stop() {
        runtime.stop()
        syncFromRuntime()
    }

    func refreshBridgeState() {
        runtime.refreshBridgeState()
        syncFromRuntime()
    }

    private func syncFromRuntime() {
        state = runtime.state
        lastPlan = runtime.lastPlan
    }
}

enum PartySessionError: LocalizedError, Equatable {
    case noPlayableOutputs

    var errorDescription: String? {
        switch self {
        case .noPlayableOutputs: return "No playable outputs are selected."
        }
    }
}
