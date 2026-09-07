import SwiftUI
import AppKit

struct JamMenuProjection: View {
    @ObservedObject var controller: JamController
    let setupPresenter: SetupPresenting

    var body: some View {
        Text("Airplayify Jam").font(.headline)
        if let lastRefresh = controller.lastRefresh {
            Text("Updated \(lastRefresh.formatted(date: .omitted, time: .shortened))")
                .font(.caption).foregroundStyle(.secondary)
        }

        Section("Outputs") {
            Button(controller.isRefreshing ? "Refreshing…" : "Refresh Outputs") {
                Task { await controller.refreshOutputs() }
            }.disabled(controller.isRefreshing)
            Menu("Available outputs (\(controller.devices.count))") {
                if controller.devices.isEmpty {
                    Text("No audio outputs found")
                } else {
                    ForEach(controller.devices) { device in
                        Label {
                            HStack {
                                Text(device.name)
                                Spacer()
                                Text(device.isAvailable ? "Ready" : "Offline")
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: device.kind == .airPlay ? "airplayaudio" : "speaker.wave.2")
                        }
                    }
                }
            }
        }

        Section("Party") {
            if controller.groups.isEmpty {
                Button("Create Everywhere Group") { controller.createEverywhere() }
            } else {
                Menu("Group: \(selectedGroupName)") {
                    ForEach(controller.groups) { group in
                        Button {
                            controller.selectedGroup = group.id
                        } label: {
                            Label(group.name, systemImage: controller.selectedGroup == group.id ? "checkmark.circle.fill" : "circle")
                        }
                    }
                    Divider()
                    Button("Rebuild Everywhere Group") { controller.createEverywhere() }
                }
                if let group = selectedGroup {
                    Button(controller.partySession.state == .stopped ? "Start AirPlay Party" : "Stop AirPlay Party") {
                        if controller.partySession.state == .stopped {
                            controller.startParty(for: group)
                        } else {
                            controller.stopParty()
                        }
                    }
                    Text(controller.localOutputStatus).font(.caption).foregroundStyle(.secondary)
                    Text("Party state: \(String(describing: controller.partySession.state))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }

        Section("Spotify Connect") {
            Text("Party Mirror = one captured stream\nConnect Lanes = one active device per account")
                .font(.caption).foregroundStyle(.secondary)
            Button("Permissions & Setup…") {
                setupPresenter.show(page: .welcome)
            }
            if controller.spotifyProfiles.isEmpty {
                Text("Configure a client ID in the setup window. OAuth tokens stay in Keychain.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Open Spotify developer dashboard") {
                    NSWorkspace.shared.open(URL(string: "https://developer.spotify.com/dashboard")!)
                }
            } else {
                ForEach(controller.spotifyProfiles) { profile in
                    Menu(profile.label) {
                        Button("Allow/Reconnect Spotify Access…") { controller.authenticateSpotify(profile) }
                        Button("Refresh devices") { controller.refreshSpotifyDevices(for: profile) }
                        Button("Transfer assigned playback") { controller.transferSpotify(for: profile) }
                        Divider()
                        ForEach(controller.spotifyDevices[profile.id] ?? []) { device in
                            Button {
                                controller.assignSpotifyDevice(device, to: profile)
                            } label: {
                                Label(device.name, systemImage: profile.assignedDeviceID == device.id ? "checkmark.circle.fill" : "circle")
                            }
                        }
                    }
                }
            }
            Text(controller.spotifyStatus).font(.caption).foregroundStyle(.secondary)
        }

        Divider()
        Button("Open Sound Settings") {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!)
        }
        Button("Quit Airplayify Jam") { NSApplication.shared.terminate(nil) }
    }

    private var selectedGroup: OutputGroup? {
        guard let selected = controller.selectedGroup else { return nil }
        return controller.groups.first(where: { $0.id == selected })
    }

    private var selectedGroupName: String {
        selectedGroup?.name ?? "Choose group"
    }
}
