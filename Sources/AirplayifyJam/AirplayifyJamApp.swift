import SwiftUI
import AppKit
import Combine

@main
struct AirplayifyJamApp: App {
    @StateObject private var controller: JamController
    @State private var menuBarInserted = true
    private let setupPresenter: SetupWindowPresenter

    init() {
        if CommandLine.arguments.contains("--list-outputs") {
            for device in AudioDeviceCatalog.devices() + AirPlayDiscovery.discover() {
                print("\(device.id)\t\(device.kind.rawValue)\t\(device.name)")
            }
            exit(EXIT_SUCCESS)
        }
        if CommandLine.arguments.contains("--setup-status") {
            print("runtime=\(AirPlayRuntime.isReady ? "ready" : "missing")")
            print("screen-capture=\(SetupAccess.screenCaptureAllowed ? "allowed" : "needs-approval-or-restart")")
            print("accessibility=\(SetupAccess.accessibilityAllowed ? "allowed" : "needs-approval-or-restart")")
            print("blackhole-installed=\(SetupAccess.virtualAudioDriverInstalled ? "yes" : "no")")
            print("blackhole-loaded=\(SetupAccess.virtualAudioDriverName == nil ? "no" : "yes")")
            print("prefer-virtual-audio=\(UserDefaults.standard.bool(forKey: SetupAccess.preferVirtualAudioKey) ? "yes" : "no")")
            exit(EXIT_SUCCESS)
        }
        if CommandLine.arguments.contains("--diagnose-permissions") {
            SetupAccess.diagnosePermissions(includeHelperProbe: CommandLine.arguments.contains("--probe-helper"))
            exit(EXIT_SUCCESS)
        }
        let controller = JamController()
        _controller = StateObject(wrappedValue: controller)
        setupPresenter = SetupWindowPresenter(controller: controller)
    }

    var body: some Scene {
        MenuBarExtra("Airplayify Jam", systemImage: "airplayaudio", isInserted: $menuBarInserted) {
            JamControlCenterView(controller: controller, setupPresenter: setupPresenter)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class JamController: ObservableObject {
    @Published private(set) var localOutputStatus = "Local outputs inactive"
    @Published var preferVirtualAudioOutput: Bool {
        didSet { UserDefaults.standard.set(preferVirtualAudioOutput, forKey: SetupAccess.preferVirtualAudioKey) }
    }
    @Published var automaticallyRefreshOutputs: Bool {
        didSet { UserDefaults.standard.set(automaticallyRefreshOutputs, forKey: SetupAccess.automaticallyRefreshOutputsKey) }
    }
    @Published var masterVolume: Double {
        didSet { UserDefaults.standard.set(masterVolume, forKey: SetupAccess.masterVolumeKey) }
    }
    @Published private(set) var outputVolumes: [String: Double]
    @Published private(set) var captureAuthorization: CaptureAuthorizationState = .checking
    @Published var captureVolumeKeys: Bool {
        didSet {
            UserDefaults.standard.set(captureVolumeKeys, forKey: SetupAccess.captureVolumeKeysKey)
            refreshMediaKeyPolicy()
        }
    }
    let outputInventory: OutputInventory
    let spotifyLanes: SpotifyLaneCoordinator
    let partySession: PartySessionController

    private var monitorTask: Task<Void, Never>?
    private var inventoryCancellable: AnyCancellable?
    private var spotifyLaneCancellable: AnyCancellable?
    private var partySessionCancellable: AnyCancellable?
    private let localOutputGroup = LocalOutputGroupManager()
    private var mediaKeyInterceptor: MediaKeyInterceptor?
    private var lastAudibleVolume: Double = 1
    private let captureService = CaptureAuthorizationService()

    var devices: [OutputDevice] { outputInventory.devices }
    var unavailableDevices: [OutputDevice] { outputInventory.unavailableDevices }
    var groups: [OutputGroup] { outputInventory.groups }
    var selectedGroup: UUID? {
        get { outputInventory.selectedGroup }
        set { outputInventory.selectedGroup = newValue }
    }
    var isRefreshing: Bool { outputInventory.isRefreshing }
    var lastRefresh: Date? { outputInventory.lastRefresh }
    var spotifyProfiles: [SpotifyProfile] { spotifyLanes.profiles }
    var spotifyDevices: [UUID: [SpotifyDevice]] { spotifyLanes.devices }
    var spotifyStatus: String { spotifyLanes.status }
    var readiness: JamReadiness {
        let selected = devices.filter(isSelected)
        return JamReadiness.evaluate(
            runtimeReady: AirPlayRuntime.isReady,
            selectedOutputCount: selected.count,
            capture: captureAuthorization,
            party: partySession.state,
            selectedOutputsAvailable: selected.allSatisfy(\.isAvailable)
        )
    }

    convenience init() {
        self.init(inventory: OutputInventory())
    }

    init(inventory: OutputInventory) {
        UserDefaults.standard.register(defaults: [
            SetupAccess.preferVirtualAudioKey: false,
            SetupAccess.automaticallyRefreshOutputsKey: true,
            SetupAccess.masterVolumeKey: 1.0,
            SetupAccess.captureVolumeKeysKey: true
        ])
        // Undo the earlier automatic BlackHole migration once ScreenCaptureKit
        // is authorized. A later explicit BlackHole choice remains untouched.
        if UserDefaults.standard.bool(forKey: SetupAccess.didMigrateToBlackHoleDefaultKey),
           SetupAccess.screenCaptureAllowed {
            UserDefaults.standard.set(false, forKey: SetupAccess.preferVirtualAudioKey)
            UserDefaults.standard.removeObject(forKey: SetupAccess.didMigrateToBlackHoleDefaultKey)
        }
        preferVirtualAudioOutput = UserDefaults.standard.bool(forKey: SetupAccess.preferVirtualAudioKey)
        automaticallyRefreshOutputs = UserDefaults.standard.bool(forKey: SetupAccess.automaticallyRefreshOutputsKey)
        masterVolume = UserDefaults.standard.double(forKey: SetupAccess.masterVolumeKey)
        outputVolumes = UserDefaults.standard.dictionary(forKey: SetupAccess.outputVolumesKey) as? [String: Double] ?? [:]
        captureVolumeKeys = UserDefaults.standard.bool(forKey: SetupAccess.captureVolumeKeysKey)
        outputInventory = inventory
        partySession = PartySessionController(localOutputs: localOutputGroup, bridge: SpotifyBridge())
        spotifyLanes = SpotifyLaneCoordinator()
        let mediaKeys = MediaKeyInterceptor()
        mediaKeys.handler = { [weak self] command in
            guard let self else { return }
            let policy = MediaKeyPolicy(takeoverEnabled: self.captureVolumeKeys, party: self.partySession.state)
            let next = policy.applying(
                command,
                to: MediaKeyVolumeState(masterVolume: self.masterVolume, lastAudibleVolume: self.lastAudibleVolume)
            )
            self.lastAudibleVolume = next.lastAudibleVolume
            self.setMasterVolume(next.masterVolume)
        }
        mediaKeyInterceptor = mediaKeys
        refreshMediaKeyPolicy()
        inventoryCancellable = inventory.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        spotifyLaneCancellable = spotifyLanes.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        partySessionCancellable = partySession.$state.sink { [weak self] _ in
            self?.objectWillChange.send()
            self?.refreshMediaKeyPolicy()
        }
        monitorTask = Task { [weak self] in
            var refreshTick = 0
            while !Task.isCancelled {
                self?.partySession.refreshBridgeState()
                if self?.automaticallyRefreshOutputs == true, refreshTick % 5 == 0 {
                    await self?.refreshOutputs()
                }
                refreshTick += 1
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        refreshCapturePreflight()
    }

    deinit {
        monitorTask?.cancel()
        localOutputGroup.deactivate()
    }

    func refresh() async {
        await refreshOutputs()
    }

    func refreshOutputs() async {
        await outputInventory.refresh()
        objectWillChange.send()
    }

    func refreshCapturePreflight() {
        // BlackHole bypasses ScreenCaptureKit/TCC entirely, so treat it as ready
        // without waiting for the helper probe or relying on a cached preflight.
        if preferVirtualAudioOutput && SetupAccess.virtualAudioAvailable {
            captureAuthorization = .authorized
            return
        }
        captureAuthorization = SetupAccess.screenCaptureAllowed ? .authorized : .denied
    }

    private func refreshMediaKeyPolicy() {
        mediaKeyInterceptor?.apply(
            MediaKeyPolicy(takeoverEnabled: captureVolumeKeys, party: partySession.state)
        )
    }

    func testCaptureAuthorization() async {
        captureAuthorization = .checking
        captureAuthorization = await captureService.probe()
    }

    func createEverywhere() {
        outputInventory.createEverywhere()
    }

    func isSelected(_ device: OutputDevice) -> Bool {
        outputInventory.selected()?.deviceIDs.contains(device.id) == true
    }

    func setSelected(_ included: Bool, for device: OutputDevice) {
        guard let groupID = selectedGroup else { return }
        outputInventory.setDevice(device, included: included, in: groupID)
        objectWillChange.send()
    }

    func volume(for device: OutputDevice) -> Double {
        outputVolumes[device.id] ?? AudioDeviceCatalog.volume(of: device) ?? masterVolume
    }

    func setVolume(_ volume: Double, for device: OutputDevice) {
        let clamped = min(max(volume, 0), 1)
        outputVolumes[device.id] = clamped
        outputVolumes[device.name] = clamped
        UserDefaults.standard.set(outputVolumes, forKey: SetupAccess.outputVolumesKey)
        if device.kind != .airPlay { AudioDeviceCatalog.setVolume(clamped, for: device) }
    }

    func setMasterVolume(_ value: Double) {
        let next = min(max(value, 0), 1)
        var current = outputVolumes
        for device in devices where isSelected(device) {
            current[device.id] = volume(for: device)
        }
        outputVolumes = VolumeScaling.scale(current, fromMaster: masterVolume, toMaster: next)
        masterVolume = next
        UserDefaults.standard.set(outputVolumes, forKey: SetupAccess.outputVolumesKey)
        for device in devices where isSelected(device) {
            if device.kind != .airPlay, let level = outputVolumes[device.id] {
                AudioDeviceCatalog.setVolume(level, for: device)
            }
        }
    }

    func activateLocalOutputs(for group: OutputGroup) {
        let selected = group.deviceIDs.compactMap { id in devices.first(where: { $0.id == id }) }
        do {
            try localOutputGroup.activate(selected, includeVirtualAudioLoopback: false)
            localOutputStatus = "Local outputs active"
        } catch {
            localOutputStatus = error.localizedDescription
        }
    }

    func deactivateLocalOutputs() {
        localOutputGroup.deactivate()
        localOutputStatus = "Local outputs inactive"
    }

    func startParty(for group: OutputGroup) {
        let plan = PartyOutputPlan(group: group, liveDevices: devices)
        partySession.start(plan: plan)
        localOutputStatus = switch partySession.state {
        case .running: "Party session running"
        case .degraded: "Party session running with offline members"
        case .failed(let message): message
        case .starting: "Starting party session"
        case .stopped: "Party session stopped"
        }
    }

    func stopParty() {
        partySession.stop()
        localOutputStatus = "Party session stopped"
    }

    func addSpotifyProfile(label: String, clientID: String) {
        spotifyLanes.addProfile(label: label, clientID: clientID)
    }

    func refreshSpotifyDevices(for profile: SpotifyProfile) {
        spotifyLanes.refreshDevices(for: profile)
    }

    func authenticateSpotify(_ profile: SpotifyProfile) {
        spotifyLanes.authenticate(profile)
    }

    func assignSpotifyDevice(_ device: SpotifyDevice, to profile: SpotifyProfile) {
        spotifyLanes.assign(device: device, to: profile)
    }

    func transferSpotify(for profile: SpotifyProfile) {
        spotifyLanes.transfer(for: profile)
    }
}
