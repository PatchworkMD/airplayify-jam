import Foundation

@MainActor
final class PartyRuntime {
    enum State: Equatable {
        case stopped
        case starting
        case running
        case degraded
        case failed(String)
    }

    private(set) var state: State = .stopped
    private(set) var lastPlan: PartyOutputPlan?

    private let localOutputs: LocalOutputActivating
    private let bridge: AirPlayBridging

    init(localOutputs: LocalOutputActivating, bridge: AirPlayBridging) {
        self.localOutputs = localOutputs
        self.bridge = bridge
    }

    func start(plan: PartyOutputPlan) {
        state = .starting
        lastPlan = plan

        guard !plan.localDevices.isEmpty || !plan.airPlayNames.isEmpty else {
            state = .failed(PartySessionError.noPlayableOutputs.localizedDescription)
            return
        }

        let hasLocalOutputs = !plan.localDevices.isEmpty
        let hasAirPlayOutputs = !plan.airPlayNames.isEmpty
        let includeVirtualAudioLoopback = hasAirPlayOutputs && bridge.requiresVirtualAudioRoute
        let needsLocalRoute = hasLocalOutputs || includeVirtualAudioLoopback
        if needsLocalRoute {
            do {
                try localOutputs.activate(
                    plan.localDevices,
                    includeVirtualAudioLoopback: includeVirtualAudioLoopback
                )
            } catch {
                localOutputs.deactivate()
                state = .failed(error.localizedDescription)
                return
            }
        }

        if plan.airPlayNames.isEmpty {
            state = plan.unavailableDevices.isEmpty ? .running : .degraded
            return
        }

        switch bridge.start(deviceNames: plan.airPlayNames) {
        case .success:
            if bridge.isRunning {
                state = bridge.isReady
                    ? (plan.unavailableDevices.isEmpty ? .running : .degraded)
                    : .starting
            } else {
                if needsLocalRoute { localOutputs.deactivate() }
                state = .failed(bridge.status == "Stopped" ? "The AirPlay sender stopped before it became ready." : bridge.status)
            }
        case .failure(let error):
            if needsLocalRoute { localOutputs.deactivate() }
            state = .failed(error.localizedDescription)
        }
    }

    func refreshBridgeState() {
        guard let lastPlan, !lastPlan.airPlayNames.isEmpty else { return }
        guard state == .starting || state == .running || state == .degraded else { return }
        bridge.refreshStatus()
        if !bridge.isRunning {
            localOutputs.deactivate()
            state = .failed(bridge.status == "Stopped" ? "The AirPlay sender stopped unexpectedly." : bridge.status)
            return
        }
        if state == .starting, bridge.isReady {
            state = lastPlan.unavailableDevices.isEmpty ? .running : .degraded
        }
    }

    func stop() {
        bridge.stop()
        localOutputs.deactivate()
        state = .stopped
        lastPlan = nil
    }
}
