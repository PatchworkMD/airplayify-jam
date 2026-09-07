import SwiftUI
import AppKit

struct SpotifyConnectSetupView: View {
    @ObservedObject var controller: JamController
    @ObservedObject var navigation: SetupNavigation
    @StateObject private var runtime = RuntimeSetupController()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var profileLabel = ""
    @State private var clientID = ""
    @State private var screenCaptureAllowed = SetupAccess.screenCaptureAllowed
    @State private var virtualAudioDriverName = SetupAccess.virtualAudioDriverName
    @State private var virtualAudioDriverInstalled = SetupAccess.virtualAudioDriverInstalled
    @State private var accessibilityAllowed = SetupAccess.accessibilityAllowed
    @AppStorage(SetupOnboardingPersistence.completionKey) private var isOnboardingComplete = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Airplayify Jam")
                            .font(.largeTitle.weight(.semibold))
                        Text("One Spotify stream. Every selected room.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    readinessBadge
                }
                Picker("Page", selection: $navigation.page) {
                    Text("Setup").tag(SetupPage.welcome)
                    Text("Outputs").tag(SetupPage.outputs)
                    Text("Spotify").tag(SetupPage.spotify)
                    Text("Help").tag(SetupPage.diagnostics)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(24)
            .background(.bar)

            Divider()

            ScrollView {
                Group {
                    switch navigation.page {
                    case .welcome, .capture, .test: setupPage
                    case .outputs: outputsPage
                    case .spotify: spotifyPage
                    case .diagnostics: helpPage
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .frame(minWidth: 680, minHeight: 700)
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: navigation.page)
        .onAppear(perform: refreshSetupStatus)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refreshSetupStatus() }
    }

    private var setupPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Get ready to play", subtitle: "Finish these checks from top to bottom. Airplayify Jam will not pretend a party started when a required component is missing.")

            GroupBox {
                HStack(spacing: 14) {
                    Image(systemName: requiredReady ? "checkmark.seal.fill" : "wand.and.stars")
                        .font(.system(size: 30))
                        .foregroundStyle(requiredReady ? Color.green : Color.accentColor)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(requiredReady ? "This Mac is ready" : "One-click setup")
                            .font(.headline)
                        Text(requiredReady
                             ? "Choose outputs and press Start Party."
                             : "Installs the private sender, requests macOS access, and discovers your rooms.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(requiredReady ? "Refresh Setup" : "Set Up This Mac") {
                        runOneClickSetup()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(runtime.isInstalling)
                }
                .padding(7)
            }

            GroupBox {
                VStack(spacing: 14) {
                    readinessRow(
                        title: "AirPlay sender runtime",
                        detail: runtime.isReady ? "Python, pyatv, and FFmpeg are ready." : "Install the lightweight sender runtime once on this Mac.",
                        ready: runtime.isReady
                    ) {
                        if runtime.isInstalling {
                            ProgressView().controlSize(.small)
                        } else if !runtime.isReady {
                            Button("Install Runtime") { runtime.install() }
                        }
                    }
                    Divider()
                    readinessRow(
                        title: "Audio capture",
                        detail: captureDetail,
                        ready: captureReady
                    ) {
                        if !captureReady {
                            Button("Settings…") { SetupAccess.openScreenRecordingSettings() }
                            Button("Refresh") { refreshSetupStatus() }
                                .buttonStyle(.borderedProminent)
                        } else {
                            Button("Test Capture") {
                                Task { await controller.testCaptureAuthorization() }
                            }
                        }
                    }
                    Divider()
                    readinessRow(
                        title: "Audio outputs",
                        detail: controller.devices.isEmpty ? "No outputs discovered yet." : "\(controller.devices.count) found; \(selectedCount) selected.",
                        ready: !controller.devices.isEmpty && selectedCount > 0
                    ) {
                        Button("Choose…") { navigation.page = .outputs }
                    }
                    Divider()
                    readinessRow(
                        title: "Spotify Connect",
                        detail: controller.spotifyProfiles.isEmpty ? "Optional. AirPlay Party works without Spotify API access." : "\(controller.spotifyProfiles.count) account lane configured.",
                        ready: !controller.spotifyProfiles.isEmpty,
                        optional: true
                    ) {
                        Button("Configure…") { navigation.page = .spotify }
                    }
                }
                .padding(6)
            }

            if !runtime.message.isEmpty {
                Text(runtime.message)
                    .font(.caption)
                    .foregroundStyle(runtime.isReady ? Color.green : Color.secondary)
                    .textSelection(.enabled)
            }

            if !captureReady {
                Label(captureDetail, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
            }

            GroupBox("Capture source") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Source", selection: $controller.preferVirtualAudioOutput) {
                        Text("Screen & System Audio").tag(false)
                        Text("BlackHole 2ch").tag(true)
                    }
                    .pickerStyle(.menu)
                    .disabled(virtualAudioDriverName == nil)
                    Text(virtualAudioDriverName == nil
                         ? (virtualAudioDriverInstalled
                            ? "BlackHole is installed but Core Audio has not loaded it yet. Restart your Mac once, then refresh this page."
                            : "ScreenCaptureKit is selected. BlackHole is optional and currently not installed.")
                         : (controller.preferVirtualAudioOutput
                            ? "In macOS Sound Settings, set Output to BlackHole 2ch. Then play Spotify on this Mac and start the party here."
                            : "Choose BlackHole 2ch to avoid Screen & System Audio Recording, or keep Screen & System Audio for direct Spotify capture."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if controller.preferVirtualAudioOutput {
                        HStack {
                            Label("Sound Output must be BlackHole 2ch while the party is running.", systemImage: "speaker.wave.2.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Open Sound Settings") {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!)
                            }
                        }
                    }
                    if !virtualAudioDriverInstalled {
                        Button("Install BlackHole 2ch…") { SetupAccess.openBlackHoleInstaller() }
                    }
                }
                .padding(6)
            }

            HStack {
                Button("Refresh checks") { refreshSetupStatus() }
                Button("Test Capture") {
                    Task { await controller.testCaptureAuthorization() }
                }
                Spacer()
                Button("Open menu-bar controls") { NSApplication.shared.keyWindow?.close() }
                Button("Start Party") { startSelectedParty() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!requiredReady || selectedGroup == nil)
            }
        }
    }

    private var outputsPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Choose your rooms", subtitle: "Use + to add an output and − to remove it. Refresh replaces the live inventory instead of appending duplicates. Local HDMI, USB, and Mac volume changes happen through Core Audio; AirPlay volume is applied when the party sender connects.")

            GroupBox {
                VStack(spacing: 6) {
                    HStack {
                        Picker("Group", selection: Binding(
                            get: { controller.selectedGroup },
                            set: { controller.selectedGroup = $0 }
                        )) {
                            ForEach(controller.groups) { group in Text(group.name).tag(Optional(group.id)) }
                        }
                        .pickerStyle(.menu)
                        Spacer()
                        Button(controller.isRefreshing ? "Refreshing…" : "Refresh Outputs") {
                            Task { await controller.refreshOutputs() }
                        }
                        .disabled(controller.isRefreshing)
                    }
                    Divider()
                    if controller.devices.isEmpty {
                        ContentUnavailableView("No outputs found", systemImage: "speaker.slash", description: Text("Make sure the Roku devices and this Mac are on the same Wi-Fi, then refresh."))
                            .frame(height: 230)
                    } else {
                        ForEach(controller.devices) { device in
                            OutputControlRow(controller: controller, device: device)
                            if device.id != controller.devices.last?.id { Divider().padding(.leading, 38) }
                        }
                    }
                }
                .padding(6)
            }

            if !controller.unavailableDevices.isEmpty {
                GroupBox("Unavailable saved outputs") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("These devices are saved in a group but were not found on the network. Use − to remove one, or wake it and refresh.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(controller.unavailableDevices) { device in
                            OutputControlRow(controller: controller, device: device)
                        }
                    }
                    .padding(6)
                }
            }

            Toggle("Automatically refresh available outputs", isOn: $controller.automaticallyRefreshOutputs)
                .toggleStyle(.switch)

            #if !APP_STORE
            GroupBox("Mac volume keys") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Control selected outputs with Volume Up, Volume Down, and Mute", isOn: $controller.captureVolumeKeys)
                        .toggleStyle(.switch)
                    HStack {
                        Label(accessibilityAllowed ? "Hardware key control is ready" : "Accessibility approval is required to take over global volume keys", systemImage: accessibilityAllowed ? "checkmark.circle.fill" : "keyboard.badge.ellipsis")
                            .foregroundStyle(accessibilityAllowed ? Color.green : Color.orange)
                        Spacer()
                        if !accessibilityAllowed {
                            Button("Allow…") { accessibilityAllowed = SetupAccess.requestAccessibilityAccess() }
                            Button("Settings…") { SetupAccess.openAccessibilitySettings() }
                            Button("Restart App") { SetupAccess.restartApplication() }
                        }
                    }
                    Text("When enabled, the keys change Airplayify Jam's master level and all selected local outputs. AirPlay receivers receive the chosen levels when the sender connects.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(6)
            }
            #else
            Text("Use the volume sliders in the menu to adjust your Party.")
                .font(.caption).foregroundStyle(.secondary)
            #endif

            HStack {
                Button("Open Sound Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!)
                }
                Spacer()
                Button("Back") { navigation.page = .welcome }
                Button("Start Party") { startSelectedParty() }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedGroup == nil || selectedCount == 0)
            }
        }
    }

    private var spotifyPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Spotify Connect lanes", subtitle: "This is optional remote control—not the AirPlay audio path. Each Spotify account controls one active Connect device. Tokens stay in macOS Keychain; no client secret is used or shipped.")

            GroupBox("Add an account") {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Profile name, e.g. Home", text: $profileLabel)
                    TextField("Spotify client ID", text: $clientID)
                        .font(.system(.body, design: .monospaced))
                    HStack {
                        Button("Add Profile") {
                            controller.addSpotifyProfile(label: profileLabel, clientID: clientID)
                            profileLabel = ""
                            clientID = ""
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(profileLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("Open Spotify Dashboard") {
                            NSWorkspace.shared.open(URL(string: "https://developer.spotify.com/dashboard")!)
                        }
                        Spacer()
                    }
                    Text("Redirect URI: airplayifyjam://spotify/callback")
                        .font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                }
                .padding(6)
            }

            if !controller.spotifyProfiles.isEmpty {
                GroupBox("Configured accounts") {
                    VStack(spacing: 10) {
                        ForEach(controller.spotifyProfiles) { profile in
                            HStack {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                VStack(alignment: .leading) {
                                    Text(profile.label).font(.headline)
                                    Text(profile.clientID).font(.caption.monospaced()).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Allow/Reconnect…") { controller.authenticateSpotify(profile) }
                                Button("Refresh Devices") { controller.refreshSpotifyDevices(for: profile) }
                            }
                        }
                    }
                    .padding(6)
                }
            }

            Text(controller.spotifyStatus).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            HStack { Spacer(); Button("Done") { navigation.page = .welcome } }
        }
    }

    private var helpPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("How Airplayify Jam works", subtitle: "Use this recovery order whenever music is not coming out of every room.")
            helpStep(1, "Play Spotify on this Mac", "AirPlay Party captures one stream from the Mac. Spotify Connect lanes only transfer playback and do not create multiple independent streams from one account.")
            helpStep(2, "Select every output", "Open Outputs, enable the Roku/AirPlay receivers and any local HDMI, USB, or Mac speakers, then set their levels.")
            helpStep(3, "Pass the readiness checks", "The sender runtime, FFmpeg, and Screen & System Audio permission must all be ready before Start Party is enabled.")
            helpStep(4, "Start from the menu bar", "Click the AirPlayify icon, verify the selected count, then press the blue Play button. A red or orange status includes the real failure reason.")
            helpStep(5, "If a Roku disappears", "Wake the TV/Roku, confirm it is on the same Wi-Fi, then choose Refresh. AirPlay receiver names must match the selected output.")

            GroupBox("Still stuck?") {
                HStack {
                    Button("Refresh Everything") {
                        refreshSetupStatus()
                        Task { await controller.refreshOutputs() }
                    }
                    Button("Test Capture") {
                        Task { await controller.testCaptureAuthorization() }
                    }
                    Button("Open Screen Recording Settings") { SetupAccess.openScreenRecordingSettings() }
                    Button("Open Sound Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!)
                    }
                }
                .padding(6)
            }
        }
    }

    private var readinessBadge: some View {
        HStack(spacing: 10) {
            Gauge(value: Double(readinessScore), in: 0...4) { EmptyView() }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(requiredReady ? .green : .orange)
                .frame(width: 34, height: 34)
                .accessibilityLabel("Setup readiness")
                .accessibilityValue("\(readinessScore) of 4 checks ready")
            VStack(alignment: .leading) {
                Text("\(readinessScore)/4 ready").font(.headline.monospacedDigit())
                Text(requiredReady ? "Ready for AirPlay Party" : "Setup needed")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.title2.weight(.semibold))
            Text(subtitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func readinessRow<Actions: View>(title: String, detail: String, ready: Bool, optional: Bool = false, @ViewBuilder actions: () -> Actions) -> some View {
        HStack(spacing: 12) {
            Image(systemName: ready ? "checkmark.circle.fill" : optional ? "circle.dashed" : "exclamationmark.circle.fill")
                .font(.title2)
                .foregroundStyle(ready ? Color.green : optional ? Color.secondary : Color.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            actions()
        }
        .accessibilityElement(children: .combine)
    }

    private func helpStep(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)").font(.headline.monospacedDigit()).foregroundStyle(.white)
                .frame(width: 30, height: 30).background(Color.accentColor, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var selectedGroup: OutputGroup? { controller.groups.first(where: { $0.id == controller.selectedGroup }) }
    private var selectedCount: Int { controller.devices.filter(controller.isSelected).count }
    private var readinessScore: Int {
        (runtime.isReady ? 1 : 0) + (captureReady ? 1 : 0) + (selectedCount > 0 ? 1 : 0) + (!controller.spotifyProfiles.isEmpty ? 1 : 0)
    }
    private var requiredReady: Bool {
        runtime.isReady && captureReady && selectedCount > 0
    }
    private var captureReady: Bool {
        CaptureReadiness.isReady(
            preferVirtualAudio: controller.preferVirtualAudioOutput,
            virtualAudioAvailable: virtualAudioDriverName != nil,
            screenCaptureAllowed: screenCaptureAllowed,
            authorization: controller.captureAuthorization
        )
    }
    private var captureDetail: String {
        if controller.preferVirtualAudioOutput && virtualAudioDriverName != nil { return "BlackHole virtual audio is available." }
        if !controller.preferVirtualAudioOutput && screenCaptureAllowed {
            return "Screen & System Audio Recording is allowed. Open Spotify when you start a party."
        }
        switch controller.captureAuthorization {
        case .authorized: return "The signed Spotify capture helper is authorized."
        case .spotifyNotRunning: return "Capture is authorized; open Spotify when you start a party."
        case .denied: return "Enable Airplayify Jam in Screen & System Audio Recording, then refresh."
        case .captureFailed(let message): return message
        case .checking: return "Checking the signed Spotify capture helper…"
        case .restartRequired, .notRequested: return "Enable Airplayify Jam in Screen & System Audio Recording, then refresh."
        }
    }

    private func startSelectedParty() {
        guard let selectedGroup else { return }
        isOnboardingComplete = true
        controller.startParty(for: selectedGroup)
    }

    private func runOneClickSetup() {
        if !runtime.isReady { runtime.install() }
        SetupAccess.openScreenRecordingSettings()
        refreshSetupStatus()
        Task { await controller.refreshOutputs() }
    }

    private func refreshSetupStatus() {
        screenCaptureAllowed = SetupAccess.screenCaptureAllowed
        virtualAudioDriverName = SetupAccess.virtualAudioDriverName
        virtualAudioDriverInstalled = SetupAccess.virtualAudioDriverInstalled
        accessibilityAllowed = SetupAccess.accessibilityAllowed
        runtime.refresh()
        // Re-evaluate the default capture source now that BlackHole availability
        // may have changed, then refresh the authorization state that depends on it.
        controller.refreshCapturePreflight()
        Task { await controller.refreshOutputs() }
    }
}
