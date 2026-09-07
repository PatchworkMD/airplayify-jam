import SwiftUI
import AppKit

struct JamControlCenterView: View {
    @ObservedObject var controller: JamController
    let setupPresenter: SetupPresenting
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            header
            statusCard
            spotifyCard
            outputsCard
            groupCard
            footer
        }
        .padding(10)
        .frame(width: 350)
        .background(.ultraThinMaterial)
        .task { await controller.refreshOutputs() }
    }

    private var header: some View {
        HStack {
            Text("AIRPLAYIFY JAM")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(2.2)
                .foregroundStyle(.secondary)
            Spacer()
            Button { setupPresenter.show(page: SetupRouting.page(for: .help)) } label: {
                Image(systemName: "questionmark.circle")
            }
            .buttonStyle(.plain)
            .help("Setup & Help")
            Button { setupPresenter.show(page: SetupRouting.page(for: .gear)) } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .padding(.horizontal, 4)
    }

    private var statusCard: some View {
        card {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 9, height: 9)
                        .shadow(color: statusColor.opacity(0.65), radius: 5)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(statusTitle).font(.headline)
                        Text(statusDetail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button(action: toggleParty) {
                        Image(systemName: isActive ? "stop.fill" : "play.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 30, height: 30)
                            .foregroundStyle(.white)
                            .background(isActive ? Color.red : Color.accentColor, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedGroup == nil || !controller.readiness.canStart && !isActive)
                    .help(isActive ? "Stop AirPlay Party" : "Start AirPlay Party")
                }
                HStack(spacing: 9) {
                    Image(systemName: controller.masterVolume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .foregroundStyle(.secondary)
                    Slider(value: Binding(
                        get: { controller.masterVolume },
                        set: { controller.setMasterVolume($0) }
                    ), in: 0...1)
                    Text("\(Int(controller.masterVolume * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 35, alignment: .trailing)
                }
            }
        }
    }

    private var spotifyCard: some View {
        card {
            VStack(spacing: 8) {
                sectionHeader("SPOTIFY", detail: controller.spotifyProfiles.isEmpty ? "SETUP" : "\(controller.spotifyProfiles.count) LANE\(controller.spotifyProfiles.count == 1 ? "" : "S")")
                if controller.spotifyProfiles.isEmpty {
                    Button {
                        setupPresenter.show(page: SetupRouting.page(for: .connectSpotify))
                    } label: {
                        Label("Connect Spotify", systemImage: "music.note")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    Text("Spotify Connect is optional; AirPlay Party mirrors audio playing on this Mac.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(controller.spotifyProfiles) { profile in
                        HStack(spacing: 9) {
                            Image(systemName: "music.note")
                                .frame(width: 28, height: 28)
                                .foregroundStyle(.white)
                                .background(Color.green, in: RoundedRectangle(cornerRadius: 7))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(profile.label).font(.callout.weight(.medium))
                                Text(spotifyDeviceName(for: profile) ?? "Choose a Spotify Connect device")
                                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Button { controller.refreshSpotifyDevices(for: profile) } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.plain)
                            .help("Refresh Spotify devices")
                        }
                    }
                }
            }
        }
    }

    private var outputsCard: some View {
        card {
            VStack(spacing: 5) {
                sectionHeader("OUTPUT", detail: "\(selectedCount) OF \(controller.devices.count) SELECTED")
                if controller.devices.isEmpty {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Looking for audio outputs…").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                } else {
                    ForEach(controller.devices) { device in
                        OutputControlRow(controller: controller, device: device)
                    }
                }
            }
        }
    }

    private var groupCard: some View {
        card {
            VStack(spacing: 8) {
                sectionHeader("PRESET", detail: nil)
                HStack {
                    Picker("Group", selection: Binding(
                        get: { controller.selectedGroup },
                        set: { controller.selectedGroup = $0 }
                    )) {
                        ForEach(controller.groups) { group in
                            Text(group.name).tag(Optional(group.id))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    Spacer()
                    Button("Save") { controller.createEverywhere() }
                        .buttonStyle(.borderless)
                        .help("Rebuild Everywhere from discovered outputs")
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button(controller.isRefreshing ? "Refreshing…" : "Refresh") {
                Task { await controller.refreshOutputs() }
            }
            .buttonStyle(.plain)
            .disabled(controller.isRefreshing)
            Spacer()
            Button("Setup & Help…") { setupPresenter.show(page: .welcome) }
                .buttonStyle(.plain)
            Menu {
                Button("Open Sound Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!)
                }
                Divider()
                Button("Quit Airplayify Jam") { NSApplication.shared.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(11)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.1)))
    }

    private func sectionHeader(_ title: String, detail: String?) -> some View {
        HStack {
            Text(title).font(.caption2.weight(.semibold)).tracking(1.8).foregroundStyle(.secondary)
            Spacer()
            if let detail { Text(detail).font(.caption2).foregroundStyle(.tertiary) }
        }
    }

    private var selectedGroup: OutputGroup? { controller.groups.first(where: { $0.id == controller.selectedGroup }) }
    private func spotifyDeviceName(for profile: SpotifyProfile) -> String? {
        guard let assigned = profile.assignedDeviceID else { return nil }
        return controller.spotifyDevices[profile.id]?.first(where: { $0.id == assigned })?.name
    }
    private var selectedCount: Int { controller.devices.filter(controller.isSelected).count }
    private var isActive: Bool { controller.partySession.state != .stopped && !isFailed }
    private var isFailed: Bool { if case .failed = controller.partySession.state { return true }; return false }
    private var statusTitle: String {
        switch controller.partySession.state {
        case .stopped: controller.readiness.title
        case .starting: "Starting…"
        case .running: "Playing"
        case .degraded: "Playing with offline outputs"
        case .failed: "Needs attention"
        }
    }
    private var statusDetail: String {
        switch controller.partySession.state {
        case .starting: "Connecting selected outputs…"
        case .running: "Adjust the volume or stop the Party."
        case .degraded: "Some outputs are offline. Stop the Party to end playback."
        case .stopped, .failed: controller.readiness.detail
        }
    }
    private var statusColor: Color {
        switch controller.partySession.state {
        case .running: .green
        case .starting, .degraded: .orange
        case .failed: .red
        case .stopped:
            switch controller.readiness.severity {
            case .ready: .green
            case .attention: .orange
            case .blocked: .red
            }
        }
    }
    private func toggleParty() {
        guard let selectedGroup else { return }
        let work = {
            if isActive { controller.stopParty() } else { controller.startParty(for: selectedGroup) }
        }
        if reduceMotion { work() } else { withAnimation(.snappy(duration: 0.25), work) }
    }
}

struct OutputControlRow: View {
    @ObservedObject var controller: JamController
    let device: OutputDevice

    var body: some View {
        let selected = controller.isSelected(device)
        HStack(spacing: 9) {
            Button { controller.setSelected(!selected, for: device) } label: {
                Image(systemName: selected ? "minus" : "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .foregroundStyle(.white)
                    .background(selected ? Color.accentColor : Color.red.opacity(0.65), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!device.isAvailable && !selected)
            .help(selected ? "Remove from party" : "Add to party")

            VStack(alignment: .leading, spacing: 1) {
                Text(device.name).font(.callout).lineLimit(1)
                Text(device.isAvailable ? deviceLabel : "Offline")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .frame(width: 112, alignment: .leading)

            if selected && device.isAvailable {
                Slider(value: Binding(
                    get: { controller.volume(for: device) },
                    set: { controller.setVolume($0, for: device) }
                ), in: 0...1)
                .controlSize(.small)
                Text("\(Int(controller.volume(for: device) * 100))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .trailing)
            } else {
                Spacer()
            }
        }
        .padding(.vertical, 4)
        .opacity(device.isAvailable ? 1 : 0.55)
    }

    private var selectedIcon: String { device.kind == .airPlay ? "airplayaudio" : "speaker.wave.2.fill" }
    private var deviceLabel: String {
        switch device.kind {
        case .airPlay: "AirPlay"
        case .hdmi: "HDMI"
        case .usb: "USB"
        case .builtIn: "Built-in"
        case .virtual: "Virtual"
        case .unknown: "Audio output"
        }
    }
}
