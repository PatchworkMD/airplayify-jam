import XCTest
@testable import AirplayifyJam

@MainActor
final class OutputInventoryTests: XCTestCase {
    func testRefreshReconcilesStaleGroupMembersAndCreatesEverywhere() async {
        let groupID = UUID()
        let store = FakeOutputGroupStore(groups: [OutputGroup(id: groupID, name: "Saved", deviceIDs: ["gone"], deviceNames: ["gone": "Bedroom Roku"])])
        let inventory = OutputInventory(
            discoverer: FakeOutputDiscoverer(devices: [OutputDevice(id: "tv", name: "LG TV", kind: .hdmi)]),
            store: store
        )

        await inventory.refresh()

        XCTAssertEqual(inventory.devices.map(\.name), ["LG TV", "Bedroom Roku"])
        XCTAssertEqual(inventory.devices.last?.isAvailable, false)
        XCTAssertEqual(inventory.groups.first?.id, groupID)
    }

    func testEmptyInventoryCreatesEverywhereFromLiveDevices() async {
        let store = FakeOutputGroupStore(groups: [])
        let inventory = OutputInventory(
            discoverer: FakeOutputDiscoverer(devices: [OutputDevice(id: "tv", name: "LG TV", kind: .hdmi)]),
            store: store
        )

        await inventory.refresh()

        XCTAssertEqual(inventory.groups.first?.name, "Everywhere")
        XCTAssertEqual(inventory.groups.first?.deviceIDs, ["tv"])
        XCTAssertEqual(store.saved.last?.first?.name, "Everywhere")
    }

    func testEverywhereExcludesPrivateAggregateEvenWhenCoreAudioCallsItBuiltIn() async {
        let store = FakeOutputGroupStore(groups: [])
        let inventory = OutputInventory(
            discoverer: FakeOutputDiscoverer(devices: [
                OutputDevice(id: "private", name: "Airplayify Local Outputs", kind: .builtIn),
                OutputDevice(id: "speaker", name: "MacBook Pro Speakers", kind: .builtIn)
            ]),
            store: store
        )

        await inventory.refresh()

        XCTAssertEqual(inventory.devices.map(\.name), ["MacBook Pro Speakers"])
        XCTAssertEqual(inventory.groups.first?.deviceIDs, ["speaker"])
    }
}

private struct FakeOutputDiscoverer: OutputDiscovering {
    let devices: [OutputDevice]
    func discover() async -> [OutputDevice] { devices }
}

private final class FakeOutputGroupStore: OutputGroupStoring, @unchecked Sendable {
    let initial: [OutputGroup]
    private(set) var saved: [[OutputGroup]] = []

    init(groups: [OutputGroup]) { self.initial = groups }
    func load() -> [OutputGroup] { initial }
    func save(_ groups: [OutputGroup]) throws { saved.append(groups) }
}
