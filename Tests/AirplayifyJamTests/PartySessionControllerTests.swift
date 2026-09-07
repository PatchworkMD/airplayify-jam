import XCTest
@testable import AirplayifyJam

final class PartySessionControllerTests: XCTestCase {
    final class LocalOutputsFake: LocalOutputActivating {
        var activated: [OutputDevice] = []
        var includedVirtualAudioLoopback = false
        var didDeactivate = false
        var shouldThrow = false

        func activate(_ devices: [OutputDevice], includeVirtualAudioLoopback: Bool) throws {
            if shouldThrow { throw LocalizedErrorStub() }
            activated = devices
            includedVirtualAudioLoopback = includeVirtualAudioLoopback
        }

        func deactivate() { didDeactivate = true }
    }

    final class BridgeFake: AirPlayBridging {
        var isRunning = false
        var isReady = true
        var status = "Stopped"
        var requiresVirtualAudioRoute = false
        var startResult: Result<Void, BridgeLaunchError> = .success(())
        var started: [String] = []
        var stopped = false
        var refreshStatusHandler: (() -> Void)?

        func start(deviceNames: [String]) -> Result<Void, BridgeLaunchError> {
            started = deviceNames
            if case .success = startResult { isRunning = true }
            return startResult
        }

        func refreshStatus() { refreshStatusHandler?() }
        func stop() { stopped = true; isRunning = false }
    }

    func testMixedSuccessBecomesRunning() {
        let local = LocalOutputsFake()
        let bridge = BridgeFake()
        let controller = PartySessionController(localOutputs: local, bridge: bridge)
        let group = OutputGroup(id: UUID(), name: "Party", deviceIDs: ["tv", "roku"])
        let plan = PartyOutputPlan(
            group: group,
            liveDevices: [
                OutputDevice(id: "tv", name: "LG TV", kind: .hdmi),
                OutputDevice(id: "roku", name: "Roku Express 4K", kind: .airPlay)
            ]
        )
        controller.start(plan: plan)
        XCTAssertEqual(local.activated.map(\.name), ["LG TV"])
        XCTAssertEqual(bridge.started, ["Roku Express 4K"])
        XCTAssertEqual(controller.state, .running)
    }

    func testLocalOnlySkipsAirPlayBridge() {
        let local = LocalOutputsFake()
        let bridge = BridgeFake()
        let controller = PartySessionController(localOutputs: local, bridge: bridge)
        let plan = PartyOutputPlan(
            group: OutputGroup(id: UUID(), name: "Local", deviceIDs: ["tv"]),
            liveDevices: [OutputDevice(id: "tv", name: "LG TV", kind: .hdmi)]
        )

        controller.start(plan: plan)

        XCTAssertEqual(local.activated.map(\.name), ["LG TV"])
        XCTAssertFalse(local.includedVirtualAudioLoopback)
        XCTAssertTrue(bridge.started.isEmpty)
        XCTAssertEqual(controller.state, .running)
    }

    func testVirtualAirPlayOnlyActivatesBlackHoleRoute() {
        let local = LocalOutputsFake()
        let bridge = BridgeFake()
        bridge.requiresVirtualAudioRoute = true
        let controller = PartySessionController(localOutputs: local, bridge: bridge)
        let plan = PartyOutputPlan(
            group: OutputGroup(id: UUID(), name: "AirPlay", deviceIDs: ["roku"]),
            liveDevices: [OutputDevice(id: "roku", name: "Roku Express 4K", kind: .airPlay)]
        )

        controller.start(plan: plan)

        XCTAssertTrue(local.activated.isEmpty)
        XCTAssertTrue(local.includedVirtualAudioLoopback)
        XCTAssertEqual(bridge.started, ["Roku Express 4K"])
        XCTAssertEqual(controller.state, .running)
    }

    func testVirtualMixedRouteIncludesPhysicalOutputsAndBlackHole() {
        let local = LocalOutputsFake()
        let bridge = BridgeFake()
        bridge.requiresVirtualAudioRoute = true
        let controller = PartySessionController(localOutputs: local, bridge: bridge)
        let plan = PartyOutputPlan(
            group: OutputGroup(id: UUID(), name: "Party", deviceIDs: ["tv", "roku"]),
            liveDevices: [
                OutputDevice(id: "tv", name: "LG TV", kind: .hdmi),
                OutputDevice(id: "roku", name: "Roku Express 4K", kind: .airPlay)
            ]
        )

        controller.start(plan: plan)

        XCTAssertEqual(local.activated.map(\.name), ["LG TV"])
        XCTAssertTrue(local.includedVirtualAudioLoopback)
        XCTAssertEqual(controller.state, .running)
    }

    func testSenderTerminationBecomesFailureAndRollsBackLocalRoute() {
        let local = LocalOutputsFake()
        let bridge = BridgeFake()
        let controller = PartySessionController(localOutputs: local, bridge: bridge)
        let plan = PartyOutputPlan(
            group: OutputGroup(id: UUID(), name: "Party", deviceIDs: ["tv", "roku"]),
            liveDevices: [
                OutputDevice(id: "tv", name: "LG TV", kind: .hdmi),
                OutputDevice(id: "roku", name: "Roku Express 4K", kind: .airPlay)
            ]
        )
        controller.start(plan: plan)
        bridge.isRunning = false
        bridge.status = "Roku disconnected"

        controller.refreshBridgeState()

        XCTAssertTrue(local.didDeactivate)
        XCTAssertEqual(controller.state, .failed("Roku disconnected"))
    }

    func testPartyRemainsStartingUntilSenderReportsReady() {
        let bridge = BridgeFake()
        bridge.isReady = false
        let controller = PartySessionController(localOutputs: LocalOutputsFake(), bridge: bridge)
        let plan = PartyOutputPlan(
            group: OutputGroup(id: UUID(), name: "AirPlay", deviceIDs: ["roku"]),
            liveDevices: [OutputDevice(id: "roku", name: "Roku Express 4K", kind: .airPlay)]
        )

        controller.start(plan: plan)
        XCTAssertEqual(controller.state, .starting)

        bridge.isReady = true
        controller.refreshBridgeState()
        XCTAssertEqual(controller.state, .running)
    }

    func testSenderStartupTimeoutFailsAndRollsBackLocalRoute() {
        let local = LocalOutputsFake()
        let bridge = BridgeFake()
        bridge.isReady = false
        bridge.refreshStatusHandler = {
            bridge.isRunning = false
            bridge.status = "AirPlay sender startup timed out before the receivers became ready."
        }
        let controller = PartySessionController(localOutputs: local, bridge: bridge)
        let plan = PartyOutputPlan(
            group: OutputGroup(id: UUID(), name: "Party", deviceIDs: ["tv", "roku"]),
            liveDevices: [
                OutputDevice(id: "tv", name: "LG TV", kind: .hdmi),
                OutputDevice(id: "roku", name: "Roku Express 4K", kind: .airPlay)
            ]
        )

        controller.start(plan: plan)
        controller.refreshBridgeState()

        XCTAssertTrue(local.didDeactivate)
        XCTAssertEqual(
            controller.state,
            .failed("AirPlay sender startup timed out before the receivers became ready.")
        )
    }

    func testAirPlayOnlyStillStartsBridge() {
        let local = LocalOutputsFake()
        let bridge = BridgeFake()
        let controller = PartySessionController(localOutputs: local, bridge: bridge)
        let group = OutputGroup(id: UUID(), name: "Party", deviceIDs: ["roku"])
        let plan = PartyOutputPlan(group: group, liveDevices: [OutputDevice(id: "roku", name: "Roku Express 4K", kind: .airPlay)])
        controller.start(plan: plan)
        XCTAssertTrue(local.activated.isEmpty)
        XCTAssertEqual(bridge.started, ["Roku Express 4K"])
        XCTAssertEqual(controller.state, .running)
    }

    func testOfflineMemberProducesDegradedState() {
        let local = LocalOutputsFake()
        let bridge = BridgeFake()
        let controller = PartySessionController(localOutputs: local, bridge: bridge)
        let group = OutputGroup(id: UUID(), name: "Party", deviceIDs: ["tv", "offline"], deviceNames: ["offline": "Bedroom Roku"])
        let plan = PartyOutputPlan(
            group: group,
            liveDevices: [OutputDevice(id: "tv", name: "LG TV", kind: .hdmi)]
        )

        controller.start(plan: plan)

        XCTAssertEqual(controller.state, .degraded)
    }

    func testEmptyPlanFailsWithoutTouchingOutputs() {
        let local = LocalOutputsFake()
        let bridge = BridgeFake()
        let controller = PartySessionController(localOutputs: local, bridge: bridge)
        let plan = PartyOutputPlan(group: OutputGroup(id: UUID(), name: "Empty", deviceIDs: []), liveDevices: [])

        controller.start(plan: plan)

        XCTAssertTrue(local.activated.isEmpty)
        XCTAssertFalse(local.didDeactivate)
        XCTAssertTrue(bridge.started.isEmpty)
        XCTAssertEqual(controller.state, .failed("No playable outputs are selected."))
    }

    func testLocalActivationFailureRollsBack() {
        let local = LocalOutputsFake()
        local.shouldThrow = true
        let bridge = BridgeFake()
        let controller = PartySessionController(localOutputs: local, bridge: bridge)
        let plan = PartyOutputPlan(
            group: OutputGroup(id: UUID(), name: "Local", deviceIDs: ["tv"]),
            liveDevices: [OutputDevice(id: "tv", name: "LG TV", kind: .hdmi)]
        )

        controller.start(plan: plan)

        XCTAssertTrue(local.didDeactivate)
        XCTAssertTrue(bridge.started.isEmpty)
        XCTAssertEqual(controller.state, .failed("Local output activation failed"))
    }

    func testBridgeFailureRollsBackLocalOutputs() {
        let local = LocalOutputsFake()
        let bridge = BridgeFake()
        bridge.startResult = .failure(.noAirPlayTargets)
        let controller = PartySessionController(localOutputs: local, bridge: bridge)
        let plan = PartyOutputPlan(
            group: OutputGroup(id: UUID(), name: "Party", deviceIDs: ["tv", "roku"]),
            liveDevices: [
                OutputDevice(id: "tv", name: "LG TV", kind: .hdmi),
                OutputDevice(id: "roku", name: "Roku Express 4K", kind: .airPlay)
            ]
        )
        controller.start(plan: plan)
        XCTAssertTrue(local.didDeactivate)
        XCTAssertEqual(controller.state, .failed("No AirPlay devices selected"))
    }

    func testStopCleansUp() {
        let local = LocalOutputsFake()
        let bridge = BridgeFake()
        let controller = PartySessionController(localOutputs: local, bridge: bridge)
        let plan = PartyOutputPlan(group: OutputGroup(id: UUID(), name: "Party", deviceIDs: []), liveDevices: [OutputDevice(id: "tv", name: "LG TV", kind: .hdmi)])
        controller.start(plan: plan)
        controller.stop()
        XCTAssertTrue(bridge.stopped)
        XCTAssertTrue(local.didDeactivate)
        XCTAssertEqual(controller.state, .stopped)
    }
}

private struct LocalizedErrorStub: LocalizedError {
    var errorDescription: String? { "Local output activation failed" }
}
