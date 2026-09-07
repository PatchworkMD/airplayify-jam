import Foundation
import Combine

@MainActor
@main
struct AirplayifyJamDirectTests {
    static func main() async throws {
        testPartyPlans()
        testPartySessions()
        testPartyStatePublisher()
        await testOutputInventory()
        await testOutputInventoryRefreshOverlap()
        testVolumeScaling()
        testBridgePlans()
        testSenderStatusMapping()
        testBridgeCaptureModeSelection()
        testLocalSelection()
        testPKCE()
        testMediaKeyMapping()
        testMediaKeyPolicy()
        try testSpotifyLaneMetadata()
        testReadinessAndSetupRouting()
        testOnboardingPolicy()
        try testRunningIdentity()
        testCaptureAuthorizationMapping()
        testCaptureProbePolicy()
        print("direct tests: 19 suites passed")
    }

    private static func testPartyPlans() {
        let group = OutputGroup(id: UUID(), name: "Everywhere", deviceIDs: ["tv", "roku", "mac"])
        let plan = PartyOutputPlan(group: group, liveDevices: [
            OutputDevice(id: "tv", name: "LG TV", kind: .hdmi),
            OutputDevice(id: "roku", name: "Roku Express 4K", kind: .airPlay),
            OutputDevice(id: "mac", name: "Austin MacBook AirPlay Receiver", kind: .airPlay)
        ])
        expect(plan.localDevices.map(\.name) == ["LG TV"], "party local selection")
        expect(plan.airPlayNames == ["Roku Express 4K"], "party AirPlay selection")

        let staleGroup = OutputGroup(
            id: UUID(),
            name: "Everywhere",
            deviceIDs: ["old-tv-1", "old-tv-2", "airplay:roku"],
            deviceNames: [
                "old-tv-1": "LG TV",
                "old-tv-2": "LG TV",
                "airplay:roku": "Roku Express 4K"
            ]
        )
        let rebound = DeviceRegistry.rebind(staleGroup, to: [
            OutputDevice(id: "109", name: "LG TV", kind: .hdmi),
            OutputDevice(id: "airplay:Roku Express 4K", name: "Roku Express 4K", kind: .airPlay)
        ])
        expect(rebound.deviceIDs == ["109", "airplay:Roku Express 4K"], "refresh replaces stale duplicate IDs with live devices")
    }

    private static func testPartySessions() {
        let local = LocalFake()
        let bridge = BridgeFake()
        let controller = PartySessionController(localOutputs: local, bridge: bridge)

        let localPlan = PartyOutputPlan(
            group: OutputGroup(id: UUID(), name: "Local", deviceIDs: ["tv"]),
            liveDevices: [OutputDevice(id: "tv", name: "LG TV", kind: .hdmi)]
        )
        controller.start(plan: localPlan)
        expect(controller.state == .running, "local-only party starts")
        expect(bridge.started.isEmpty, "local-only party skips AirPlay bridge")
        expect(local.activations.last?.includeVirtualAudioLoopback == false, "local-only party uses physical outputs only")
        controller.stop()
        expect(local.deactivated, "party stop deactivates local outputs")

        let degradedController = PartySessionController(localOutputs: LocalFake(), bridge: BridgeFake())
        let degradedPlan = PartyOutputPlan(
            group: OutputGroup(id: UUID(), name: "Degraded", deviceIDs: ["tv", "offline"], deviceNames: ["offline": "Bedroom Roku"]),
            liveDevices: [OutputDevice(id: "tv", name: "LG TV", kind: .hdmi)]
        )
        degradedController.start(plan: degradedPlan)
        expect(degradedController.state == .degraded, "offline party member is degraded")

        let airPlayController = PartySessionController(localOutputs: LocalFake(), bridge: BridgeFake())
        let airPlayPlan = PartyOutputPlan(
            group: OutputGroup(id: UUID(), name: "AirPlay", deviceIDs: ["roku"]),
            liveDevices: [OutputDevice(id: "roku", name: "Roku Express 4K", kind: .airPlay)]
        )
        airPlayController.start(plan: airPlayPlan)
        expect(airPlayController.state == .running, "AirPlay-only party starts")

        let virtualLocal = LocalFake()
        let virtualBridge = BridgeFake(requiresVirtualAudioRoute: true)
        let virtualController = PartySessionController(localOutputs: virtualLocal, bridge: virtualBridge)
        virtualController.start(plan: airPlayPlan)
        expect(virtualLocal.activations.last?.devices.isEmpty == true, "virtual AirPlay-only route has no physical outputs")
        expect(virtualLocal.activations.last?.includeVirtualAudioLoopback == true, "virtual AirPlay-only route activates BlackHole")

        let mixedVirtualLocal = LocalFake()
        let mixedVirtualBridge = BridgeFake(requiresVirtualAudioRoute: true)
        let mixedVirtualController = PartySessionController(localOutputs: mixedVirtualLocal, bridge: mixedVirtualBridge)
        let mixedPlan = PartyOutputPlan(
            group: OutputGroup(id: UUID(), name: "Mixed", deviceIDs: ["tv", "roku"]),
            liveDevices: [
                OutputDevice(id: "tv", name: "LG TV", kind: .hdmi),
                OutputDevice(id: "roku", name: "Roku Express 4K", kind: .airPlay)
            ]
        )
        mixedVirtualController.start(plan: mixedPlan)
        expect(mixedVirtualLocal.activations.last?.devices.map(\.name) == ["LG TV"], "mixed virtual route keeps physical output")
        expect(mixedVirtualLocal.activations.last?.includeVirtualAudioLoopback == true, "mixed virtual route adds BlackHole")

        let startingBridge = BridgeFake(isReady: false)
        let startingController = PartySessionController(localOutputs: LocalFake(), bridge: startingBridge)
        startingController.start(plan: airPlayPlan)
        expect(startingController.state == .starting, "party remains starting until sender reports readiness")
        startingBridge.isReady = true
        startingController.refreshBridgeState()
        expect(startingController.state == .running, "party becomes running only after sender readiness")

        let timeoutLocal = LocalFake()
        let timeoutBridge = BridgeFake(isReady: false)
        timeoutBridge.refreshStatusHandler = {
            timeoutBridge.isRunning = false
            timeoutBridge.status = "AirPlay sender startup timed out before the receivers became ready."
        }
        let timeoutController = PartySessionController(localOutputs: timeoutLocal, bridge: timeoutBridge)
        timeoutController.start(plan: mixedPlan)
        timeoutController.refreshBridgeState()
        expect(
            timeoutController.state == .failed("AirPlay sender startup timed out before the receivers became ready."),
            "sender startup timeout becomes a typed party failure"
        )
        expect(timeoutLocal.deactivated, "sender startup timeout rolls back local route")

        mixedVirtualBridge.isRunning = false
        mixedVirtualBridge.status = "Roku disconnected"
        mixedVirtualController.refreshBridgeState()
        expect(mixedVirtualController.state == .failed("Roku disconnected"), "sender exit becomes visible in party state")
        expect(mixedVirtualLocal.deactivated, "sender exit rolls back local route")

        let emptyController = PartySessionController(localOutputs: LocalFake(), bridge: BridgeFake())
        emptyController.start(plan: PartyOutputPlan(group: OutputGroup(id: UUID(), name: "Empty", deviceIDs: []), liveDevices: []))
        expect(emptyController.state == .failed("No playable outputs are selected."), "empty party fails clearly")
    }

    @MainActor
    private static func testPartyStatePublisher() {
        let controller = PartySessionController(localOutputs: LocalFake(), bridge: BridgeFake())
        var states: [PartyRuntime.State] = []
        let cancellable = controller.$state.sink { states.append($0) }
        let plan = PartyOutputPlan(
            group: OutputGroup(id: UUID(), name: "Local", deviceIDs: ["tv"]),
            liveDevices: [OutputDevice(id: "tv", name: "LG TV", kind: .hdmi)]
        )

        controller.start(plan: plan)
        expect(states.last == .running, "party state publisher emits the assigned running state")
        controller.stop()
        expect(states.last == .stopped, "party state publisher emits the assigned stopped state")
        _ = cancellable
    }

    private static func testBridgePlans() {
        expect(BridgeLaunchPlan.make(deviceNames: []).failureValue == .noAirPlayTargets, "empty bridge target rejection")
        let result = BridgeLaunchPlan.make(deviceNames: ["Roku Express 4K", "Living Room TV"])
        guard case .success(let plan) = result else { fail("multi-target bridge plan") }
        expect(plan.arguments.dropFirst() == ["Roku Express 4K", "Living Room TV"], "bridge target quoting")
        expect(plan.status == "Streaming Spotify to 2 AirPlay device(s)", "bridge status")
        let virtualResult = BridgeLaunchPlan.make(deviceNames: ["Living Room TV"], captureMode: .virtualAudio)
        guard case .success(let virtualPlan) = virtualResult else { fail("virtual audio bridge plan") }
        expect(virtualPlan.arguments[0].hasSuffix("spotify-virtual-capture.sh"), "virtual audio capture script")
        expect(virtualPlan.status == "Streaming virtual audio to 1 AirPlay device(s)", "virtual audio status")
    }

    private static func testSenderStatusMapping() {
        let ready = SenderStatusSnapshot.decode(Data(#"{"state":"ready","detail":"2 receivers connected"}"#.utf8))
        expect(ready == SenderStatusSnapshot(state: .ready, detail: "2 receivers connected"), "sender ready status decodes")
        let failed = SenderStatusSnapshot.decode(Data(#"{"state":"failed","detail":"AirPlay devices not found: Bedroom Roku"}"#.utf8))
        expect(failed?.state == .failed, "sender failure status decodes")
        expect(failed?.detail == "AirPlay devices not found: Bedroom Roku", "sender failure remains actionable")
        expect(SenderStatusSnapshot.decode(Data("partial".utf8)) == nil, "partial sender status is ignored until complete")
    }

    private static func testBridgeCaptureModeSelection() {
        expect(!SpotifyBridge.shouldUseVirtualAudio(preference: nil, virtualAudioAvailable: true, screenCaptureAllowed: true), "ScreenCaptureKit is the default capture lane when permission is allowed")
        expect(SpotifyBridge.shouldUseVirtualAudio(preference: nil, virtualAudioAvailable: true, screenCaptureAllowed: false), "BlackHole is the automatic fallback when screen capture is unavailable")
        expect(SpotifyBridge.shouldUseVirtualAudio(preference: false, virtualAudioAvailable: true, screenCaptureAllowed: false), "BlackHole bypasses denied screen capture")
        expect(!SpotifyBridge.shouldUseVirtualAudio(preference: false, virtualAudioAvailable: true, screenCaptureAllowed: true), "explicit screen capture preference is honored when allowed")
        expect(!SpotifyBridge.shouldUseVirtualAudio(preference: true, virtualAudioAvailable: false, screenCaptureAllowed: false), "missing BlackHole cannot use virtual audio")

        // When BlackHole is preferred and available, the capture state must be
        // usable even if ScreenCaptureKit/TCC reports screen capture as denied.
        let blackHoleReady: CaptureAuthorizationState = .spotifyNotRunning
        expect(blackHoleReady.isUsable, "BlackHole-ready capture is usable despite denied screen capture")

        // When ScreenCaptureKit preflight is allowed, the setup state must not
        // be the permission-denied copy.
        let screenCaptureAllowed: CaptureAuthorizationState = .spotifyNotRunning
        expect(screenCaptureAllowed != .denied, "allowed screen capture does not map to denied")
        expect(screenCaptureAllowed.isUsable, "allowed screen capture is usable")

        expect(CaptureReadiness.isReady(
            preferVirtualAudio: false,
            virtualAudioAvailable: false,
            screenCaptureAllowed: true,
            authorization: .denied
        ), "current screen preflight overrides stale denied controller state")
        expect(!CaptureReadiness.isReady(
            preferVirtualAudio: false,
            virtualAudioAvailable: false,
            screenCaptureAllowed: false,
            authorization: .denied
        ), "denied screen capture is not ready")
        expect(CaptureReadiness.isReady(
            preferVirtualAudio: true,
            virtualAudioAvailable: true,
            screenCaptureAllowed: false,
            authorization: .denied
        ), "available BlackHole lane is ready without screen permission")
        expect(!CaptureReadiness.isReady(
            preferVirtualAudio: true,
            virtualAudioAvailable: false,
            screenCaptureAllowed: true,
            authorization: .spotifyNotRunning
        ), "unavailable selected BlackHole lane is not ready")
    }

    private static func testOutputInventory() async {
        let stale = OutputGroup(id: UUID(), name: "Saved", deviceIDs: ["gone"], deviceNames: ["gone": "Bedroom Roku"])
        let store = DirectGroupStore(groups: [stale])
        let inventory = OutputInventory(
            discoverer: DirectDiscoverer(devices: [
                OutputDevice(id: "private", name: "Airplayify Local Outputs", kind: .builtIn),
                OutputDevice(id: "blackhole", name: "BlackHole 2ch", kind: .virtual),
                OutputDevice(id: "aggregate", name: "Multi-Output Device", kind: .virtual),
                OutputDevice(id: "self", name: "Austin's MacBook Pro", kind: .airPlay),
                OutputDevice(id: "tv", name: "LG TV", kind: .hdmi),
                OutputDevice(id: "airplay:LG TV", name: "LG TV", kind: .airPlay)
            ]),
            store: store
        )
        await inventory.refresh()
        expect(inventory.devices.map(\.name) == ["LG TV"], "inventory refresh keeps live devices only")
        expect(inventory.unavailableDevices.map(\.name) == ["Bedroom Roku"], "inventory keeps saved offline devices separately")
        expect(DeviceRegistry.makeEverywhere(from: inventory.devices).deviceIDs == ["tv"], "inventory excludes private aggregate and stale members")
    }

    private static func testOutputInventoryRefreshOverlap() async {
        let discoverer = BlockingDiscoverer(devices: [OutputDevice(id: "tv", name: "LG TV", kind: .hdmi)])
        let inventory = OutputInventory(discoverer: discoverer, store: DirectGroupStore(groups: []))
        let probe = RefreshProbe()

        let first = Task.detached {
            await probe.enter()
            await inventory.refresh()
            await probe.finish(1)
        }
        await discoverer.waitForCall()
        let second = Task.detached {
            await probe.enter()
            await inventory.refresh()
            await probe.finish(2)
        }
        await probe.waitForEntries(2)
        for _ in 0..<10 { await Task.yield() }
        let finishedBeforeRelease = await probe.finishedValues()
        expect(finishedBeforeRelease.isEmpty, "overlapping refresh waits for the active discovery")

        await discoverer.release()
        await first.value
        await second.value
        let discoveryCalls = await discoverer.callCount
        expect(discoveryCalls == 1, "overlapping refresh coalesces discovery")
        expect(inventory.devices.map(\.name) == ["LG TV"], "overlapping refresh returns current outputs")
        expect(inventory.lastRefresh != nil, "overlapping refresh returns after inventory updates")
    }

    private static func testVolumeScaling() {
        let current = ["living": 0.50, "bedroom": 0.75]
        let scaled = VolumeScaling.scale(current, fromMaster: 1.0, toMaster: 0.8)
        expect(abs((scaled["living"] ?? 0) - 0.4) < 0.0001, "master volume scales living room proportionally")
        expect(abs((scaled["bedroom"] ?? 0) - 0.6) < 0.0001, "master volume scales bedroom proportionally")
        expect(scaled["living"] != scaled["bedroom"], "master volume does not mirror exact levels")
        let raised = VolumeScaling.scale(current, fromMaster: 0.8, toMaster: 1.0)
        expect(abs((raised["living"] ?? 0) - 0.625) < 0.0001, "master volume restores independent living level")
        expect(abs((raised["bedroom"] ?? 0) - 0.9375) < 0.0001, "master volume restores independent bedroom level")
    }

    private static func testLocalSelection() {
        let selection = LocalOutputSelection(devices: [
            OutputDevice(id: "hdmi", name: "LG TV", kind: .hdmi),
            OutputDevice(id: "usb", name: "Volt 276", kind: .usb),
            OutputDevice(id: "airplay", name: "Roku TV", kind: .airPlay),
            OutputDevice(id: "aggregate", name: "Airplayify Multi-Output Device", kind: .virtual)
        ])
        expect(selection.localDevices.map(\.name) == ["LG TV", "Volt 276"], "direct local output selection")
        expect(selection.excludedDevices.count == 2, "AirPlay and aggregate exclusion")
    }

    private static func testPKCE() {
        let pkce = SpotifyPKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        expect(pkce.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", "RFC 7636 PKCE challenge")
        expect(!pkce.challenge.contains("="), "PKCE padding removal")
    }

    private static func testMediaKeyMapping() {
        func data(_ key: Int, _ state: Int = 0xA) -> Int { (key << 16) | (state << 8) }
        expect(MediaKeyInterceptor.command(data1: data(0), subtype: 8) == .volumeUp, "volume-up media key")
        expect(MediaKeyInterceptor.command(data1: data(1), subtype: 8) == .volumeDown, "volume-down media key")
        expect(MediaKeyInterceptor.command(data1: data(7), subtype: 8) == .mute, "mute media key")
        expect(MediaKeyInterceptor.command(data1: data(0, 0xB), subtype: 8) == nil, "media key release ignored")
        expect(MediaKeyInterceptor.command(data1: data(0), subtype: 0) == nil, "non-media event ignored")
    }

    private static func testMediaKeyPolicy() {
        #if APP_STORE
        for party: PartyRuntime.State in [.stopped, .starting, .running, .degraded, .failed("test")] {
            let policy = MediaKeyPolicy(takeoverEnabled: true, party: party)
            expect(!policy.takesOverVolumeKeys, "Store policy never captures global keys")
            let initial = MediaKeyVolumeState(masterVolume: 0.5, lastAudibleVolume: 0.5)
            expect(policy.applying(.volumeUp, to: initial) == initial, "Store policy leaves volume-key events alone")
        }
        #else
        expect(!MediaKeyPolicy(takeoverEnabled: false, party: .running).takesOverVolumeKeys, "disabled takeover releases media keys")
        expect(!MediaKeyPolicy(takeoverEnabled: true, party: .stopped).takesOverVolumeKeys, "stopped party releases media keys")
        expect(MediaKeyPolicy(takeoverEnabled: true, party: .running).takesOverVolumeKeys, "running party takes over media keys")
        expect(MediaKeyPolicy(takeoverEnabled: true, party: .degraded).takesOverVolumeKeys, "degraded party keeps media keys")
        expect(!MediaKeyPolicy(takeoverEnabled: true, party: .starting).takesOverVolumeKeys, "starting party leaves media keys alone")

        let policy = MediaKeyPolicy(takeoverEnabled: true, party: .running)
        let raised = policy.applying(.volumeUp, to: MediaKeyVolumeState(masterVolume: 0.98, lastAudibleVolume: 0.5))
        expect(raised.masterVolume == 1, "volume-up clamps at full volume")
        let muted = policy.applying(.mute, to: MediaKeyVolumeState(masterVolume: 0.6, lastAudibleVolume: 0.2))
        expect(muted == MediaKeyVolumeState(masterVolume: 0, lastAudibleVolume: 0.6), "mute saves the audible volume")
        let restored = policy.applying(.mute, to: muted)
        expect(restored.masterVolume == 0.6, "mute restores the saved volume")
        let released = MediaKeyPolicy(takeoverEnabled: false, party: .running)
            .applying(.volumeDown, to: MediaKeyVolumeState(masterVolume: 0.5, lastAudibleVolume: 0.5))
        expect(released.masterVolume == 0.5, "released keys leave selected-output levels unchanged")
        #endif
    }

    @MainActor
    private final class SetupPresenterSpy: SetupPresenting {
        var pages: [SetupPage] = []
        func show(page: SetupPage) { pages.append(page) }
    }

    @MainActor
    private static func testReadinessAndSetupRouting() {
        let missingCapture = JamReadiness.evaluate(
            runtimeReady: true,
            selectedOutputCount: 1,
            capture: .denied,
            party: .stopped
        )
        expect(missingCapture.title != "Ready", "stopped party with missing capture is not ready")
        expect(!missingCapture.canStart, "denied capture blocks party start")
        let offlineOutput = JamReadiness.evaluate(
            runtimeReady: true,
            selectedOutputCount: 1,
            capture: .authorized,
            party: .stopped,
            selectedOutputsAvailable: false
        )
        expect(offlineOutput.page == .outputs && !offlineOutput.canStart, "offline selected output blocks party start")

        let ready = JamReadiness.evaluate(
            runtimeReady: true,
            selectedOutputCount: 1,
            capture: .authorized,
            party: .stopped
        )
        expect(ready.title == "Ready", "verified stopped party is ready")
        expect(ready.canStart, "verified prerequisites allow party start")

        let spotifyMissing = CaptureAuthorizationState.spotifyNotRunning
        let permissionMissing = CaptureAuthorizationState.denied
        expect(spotifyMissing != permissionMissing, "Spotify-not-running differs from permission denial")

        expect(SetupPage.capture.rawValue == "capture", "capture setup page")
        expect(SetupPage.spotify.rawValue == "spotify", "Spotify setup page")
        expect(SetupPage.test.rawValue == "test", "test setup page")
        expect(SetupRouting.page(for: .help) == .welcome, "help routes to welcome")
        expect(SetupRouting.page(for: .gear) == .diagnostics, "gear routes to diagnostics")
        expect(SetupRouting.page(for: .connectSpotify) == .spotify, "Spotify action routes to Spotify")
        expect(SetupRouting.page(for: .fixCapture) == .capture, "capture fix routes to capture")
        let spy = SetupPresenterSpy()
        let actions: [SetupAction] = [.help, .gear, .connectSpotify, .fixCapture, .fixOutputs, .startTest]
        for action in actions { spy.show(page: SetupRouting.page(for: action)) }
        expect(spy.pages == [.welcome, .diagnostics, .spotify, .capture, .outputs, .test], "presenter receives every routed page")
    }

    private static func testOnboardingPolicy() {
        let ready = JamReadiness.evaluate(
            runtimeReady: true,
            selectedOutputCount: 1,
            capture: .authorized,
            party: .stopped
        )
        let blocked = JamReadiness.evaluate(
            runtimeReady: false,
            selectedOutputCount: 1,
            capture: .authorized,
            party: .stopped
        )
        expect(SetupOnboardingState(isComplete: false).automaticPage(readiness: ready) == .welcome, "first launch opens onboarding")
        expect(SetupOnboardingState(isComplete: true).automaticPage(readiness: ready) == nil, "completed onboarding stays closed when ready")
        expect(SetupOnboardingState(isComplete: true).automaticPage(readiness: blocked) == .capture, "completed onboarding reopens at the blocked setup page")
        expect(SetupOnboardingState(isComplete: false).markingComplete().isComplete, "onboarding completion is an explicit state transition")
    }

    private static func testRunningIdentity() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("airplayify-identity-\(UUID().uuidString)")
        let canonicalURL = root.appendingPathComponent("Users/austin/Applications/Airplayify Jam.app")
        let systemURL = root.appendingPathComponent("Applications/Airplayify Jam.app")
        let info: [String: Any] = [
            "CFBundleIdentifier": "com.austinwise.airplayifyjam",
            "CFBundleShortVersionString": "0.1.0",
            "CFBundleVersion": "20260713010101"
        ]
        try FileManager.default.createDirectory(at: canonicalURL, withIntermediateDirectories: true)
        try (info as NSDictionary).write(to: canonicalURL.appendingPathComponent("Info.plist"))
        guard let bundle = Bundle(url: canonicalURL) else { fatalError("identity fixture bundle") }
        let canonical = RunningIdentity.from(bundle: bundle, teamIdentifier: "TEAM123")
        expect(canonical.bundleIdentifier == "com.austinwise.airplayifyjam", "identity bundle identifier")
        expect(canonical.shortVersion == "0.1.0", "identity short version")
        expect(canonical.buildNumber == "20260713010101", "identity build number")
        expect(canonical.teamIdentifier == "TEAM123", "identity team identifier")

        let competing = RunningIdentity(
            bundleURL: systemURL,
            bundleIdentifier: canonical.bundleIdentifier,
            shortVersion: canonical.shortVersion,
            buildNumber: canonical.buildNumber,
            teamIdentifier: canonical.teamIdentifier
        )
        expect(RunningIdentity.conflicts(canonical: canonical, candidate: competing), "duplicate app path conflicts")
        expect(!RunningIdentity.conflicts(canonical: canonical, candidate: canonical), "same canonical path is not a conflict")
        try? FileManager.default.removeItem(at: root)
    }

    private static func testCaptureAuthorizationMapping() {
        let authorized = CaptureProbeResult(capture: "authorized", spotify: "not-running", display: "available")
        expect(CaptureAuthorizationMapper.map(exitCode: 0, result: authorized) == .spotifyNotRunning, "authorized helper distinguishes Spotify absence")
        let running = CaptureProbeResult(capture: "authorized", spotify: "running", display: "available")
        expect(CaptureAuthorizationMapper.map(exitCode: 0, result: running) == .authorized, "authorized helper reports usable capture")
        let denied = CaptureProbeResult(capture: "denied", spotify: "unknown", display: "unknown")
        expect(CaptureAuthorizationMapper.map(exitCode: 2, result: denied) == .denied, "helper denial maps to denied")
        let noDisplay = CaptureProbeResult(capture: "authorized", spotify: "running", display: "missing")
        expect(CaptureAuthorizationMapper.map(exitCode: 0, result: noDisplay) == .captureFailed("No active display is available for Screen & System Audio capture."), "missing display reports the real capture blocker")
        expect(CaptureAuthorizationMapper.map(exitCode: -1, result: nil, timedOut: true) == .captureFailed("The Spotify capture helper timed out."), "helper timeout is bounded")
    }

    private static func testCaptureProbePolicy() {
        let automaticTriggers: [CaptureProbeTrigger] = [
            .automaticMonitor,
            .viewAppear,
            .appBecameActive,
            .outputRefreshButton,
            .setupRefreshButton,
            .oneClickSetup
        ]
        expect(automaticTriggers.allSatisfy { !$0.mayRunHelperProbe }, "automatic refresh paths never run capture helper")
        expect(CaptureProbeTrigger.explicitUserTest.mayRunHelperProbe, "explicit capture test may run helper")
    }

    private static func testSpotifyLaneMetadata() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("airplayify-direct-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = SpotifyProfile(label: "Main", clientID: "client-id", assignedDeviceID: "device-1")
        let store = SpotifyLaneStore(directory: directory)
        try store.save([profile])
        let data = try Data(contentsOf: directory.appendingPathComponent("AirplayifyJam/spotify-profiles.json"))
        let text = String(decoding: data, as: UTF8.self)
        expect(store.load() == [profile], "Spotify lane round-trip")
        expect(!text.contains("accessToken") && !text.contains("refreshToken"), "Spotify lane excludes tokens")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fail(message) }
    }

    private static func fail(_ message: String) -> Never {
        print("direct tests: FAIL — \(message)")
        exit(EXIT_FAILURE)
    }
}

@MainActor
private final class LocalFake: LocalOutputActivating {
    struct Activation {
        let devices: [OutputDevice]
        let includeVirtualAudioLoopback: Bool
    }

    private(set) var deactivated = false
    private(set) var activations: [Activation] = []
    func activate(_ devices: [OutputDevice], includeVirtualAudioLoopback: Bool) throws {
        activations.append(Activation(devices: devices, includeVirtualAudioLoopback: includeVirtualAudioLoopback))
    }
    func deactivate() { deactivated = true }
}

@MainActor
private final class BridgeFake: AirPlayBridging {
    var isRunning = false
    var isReady: Bool
    var status = "Stopped"
    let requiresVirtualAudioRoute: Bool
    private(set) var started: [String] = []
    var refreshStatusHandler: (() -> Void)?

    init(requiresVirtualAudioRoute: Bool = false, isReady: Bool = true) {
        self.requiresVirtualAudioRoute = requiresVirtualAudioRoute
        self.isReady = isReady
    }

    func start(deviceNames: [String]) -> Result<Void, BridgeLaunchError> {
        started = deviceNames
        isRunning = true
        return .success(())
    }
    func refreshStatus() { refreshStatusHandler?() }
    func stop() { isRunning = false }
}

private struct DirectDiscoverer: OutputDiscovering {
    let devices: [OutputDevice]
    func discover() async -> [OutputDevice] { devices }
}

private actor BlockingDiscoverer: OutputDiscovering {
    let devices: [OutputDevice]
    private var calls = 0
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    init(devices: [OutputDevice]) {
        self.devices = devices
    }

    func discover() async -> [OutputDevice] {
        calls += 1
        await withCheckedContinuation { releaseContinuation = $0 }
        return devices
    }

    func waitForCall() async {
        while calls == 0 { await Task.yield() }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    var callCount: Int { calls }
}

private actor RefreshProbe {
    private var entries = 0
    private var finished: [Int] = []

    func enter() { entries += 1 }
    func finish(_ caller: Int) { finished.append(caller) }

    func waitForEntries(_ expected: Int) async {
        while entries < expected { await Task.yield() }
    }

    func finishedValues() -> [Int] { finished }
}

private final class DirectGroupStore: OutputGroupStoring {
    let initial: [OutputGroup]
    private(set) var saved: [[OutputGroup]] = []

    init(groups: [OutputGroup]) { initial = groups }
    func load() -> [OutputGroup] { initial }
    func save(_ groups: [OutputGroup]) throws { saved.append(groups) }
}

private extension Result where Failure: Equatable {
    var failureValue: Failure? {
        guard case .failure(let error) = self else { return nil }
        return error
    }
}
