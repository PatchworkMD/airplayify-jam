import Foundation
import Combine

protocol OutputDiscovering: Sendable {
    func discover() async -> [OutputDevice]
}

struct LiveOutputDiscoverer: OutputDiscovering {
    func discover() async -> [OutputDevice] {
        await Task.detached(priority: .utility) {
            AudioDeviceCatalog.devices() + AirPlayDiscovery.discover(timeout: 1)
        }.value
    }
}

protocol OutputGroupStoring {
    func load() -> [OutputGroup]
    func save(_ groups: [OutputGroup]) throws
}

extension GroupStore: OutputGroupStoring {}

@MainActor
final class OutputInventory: ObservableObject {
    @Published private(set) var devices: [OutputDevice] = []
    @Published private(set) var unavailableDevices: [OutputDevice] = []
    @Published private(set) var groups: [OutputGroup]
    @Published var selectedGroup: UUID?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefresh: Date?

    private let discoverer: OutputDiscovering
    private let store: OutputGroupStoring
    private var refreshTask: Task<Void, Never>?

    init(
        discoverer: OutputDiscovering = LiveOutputDiscoverer(),
        store: OutputGroupStoring = GroupStore()
    ) {
        self.discoverer = discoverer
        self.store = store
        let loaded = store.load()
        let sanitized = loaded.map(DeviceRegistry.sanitize)
        self.groups = sanitized
        self.selectedGroup = sanitized.first(where: { $0.name == "Everywhere" })?.id ?? sanitized.first?.id
        if sanitized != loaded { try? store.save(sanitized) }
    }

    func refresh() async {
        if let refreshTask {
            await refreshTask.value
            return
        }
        isRefreshing = true
        let refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performRefresh()
        }
        self.refreshTask = refreshTask
        await refreshTask.value
        self.refreshTask = nil
        isRefreshing = false
    }

    private func performRefresh() async {
        let live = DeviceRegistry.displayable(await discoverer.discover())
        let reboundGroups = groups.map { DeviceRegistry.rebind($0, to: live) }
        if reboundGroups != groups {
            groups = reboundGroups
            try? store.save(groups)
        }
        let reconciled = DeviceRegistry.reconcile(live: live, groups: groups)
        devices = reconciled.filter(\.isAvailable)
        unavailableDevices = reconciled.filter { !$0.isAvailable }
        if groups.isEmpty, !live.isEmpty {
            createEverywhere(from: live)
        }
        lastRefresh = Date()
    }

    func createEverywhere() {
        createEverywhere(from: devices)
    }

    func selected() -> OutputGroup? {
        guard let selectedGroup else { return nil }
        return groups.first(where: { $0.id == selectedGroup })
    }

    func setDevice(_ device: OutputDevice, included: Bool, in groupID: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        if included {
            if !groups[index].deviceIDs.contains(device.id) {
                groups[index].deviceIDs.append(device.id)
            }
            groups[index].deviceNames[device.id] = device.name
        } else {
            groups[index].deviceIDs.removeAll(where: { $0 == device.id })
        }
        try? store.save(groups)
    }

    private func createEverywhere(from devices: [OutputDevice]) {
        let group = DeviceRegistry.makeEverywhere(from: devices)
        groups = [group]
        selectedGroup = group.id
        try? store.save(groups)
    }
}
