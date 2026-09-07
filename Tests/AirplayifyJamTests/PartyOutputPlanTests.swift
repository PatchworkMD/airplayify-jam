import XCTest
@testable import AirplayifyJam

final class PartyOutputPlanTests: XCTestCase {
    func testMixedGroupSeparatesLocalAirPlayAndUnavailable() {
        let group = OutputGroup(id: UUID(), name: "Party", deviceIDs: ["tv", "roku", "missing"], deviceNames: ["missing": "Missing Speaker"])
        let live = [
            OutputDevice(id: "tv", name: "LG TV", kind: .hdmi),
            OutputDevice(id: "roku", name: "Roku Express 4K", kind: .airPlay),
            OutputDevice(id: "multi", name: "Airplayify Multi-Output Device", kind: .virtual)
        ]

        let plan = PartyOutputPlan(group: group, liveDevices: live)
        XCTAssertEqual(plan.localDevices.map(\.name), ["LG TV"])
        XCTAssertEqual(plan.airPlayNames, ["Roku Express 4K"])
        XCTAssertEqual(plan.unavailableDevices.map(\.name), ["Missing Speaker"])
    }

    func testAirPlayOnlyGroupKeepsOnlyTargets() {
        let group = OutputGroup(id: UUID(), name: "AirPlay", deviceIDs: ["roku", "macbook"])
        let live = [
            OutputDevice(id: "roku", name: "Roku Express 4K", kind: .airPlay),
            OutputDevice(id: "macbook", name: "Austin MacBook AirPlay Receiver", kind: .airPlay)
        ]

        let plan = PartyOutputPlan(group: group, liveDevices: live)
        XCTAssertEqual(plan.localDevices, [])
        XCTAssertEqual(plan.airPlayNames, ["Roku Express 4K"])
    }

    func testLocalOnlyGroupExcludesVirtualAndTuttiOutputs() {
        let group = OutputGroup(id: UUID(), name: "Local", deviceIDs: ["tv", "tutti", "virtual"])
        let live = [
            OutputDevice(id: "tv", name: "Volt 276", kind: .usb),
            OutputDevice(id: "tutti", name: "Tutti Aggregate", kind: .virtual),
            OutputDevice(id: "virtual", name: "Airplayify Multi-Output Device", kind: .virtual)
        ]

        let plan = PartyOutputPlan(group: group, liveDevices: live)
        XCTAssertEqual(plan.localDevices.map(\.name), ["Volt 276"])
        XCTAssertEqual(plan.airPlayNames, [])
    }

    func testPrivateAirplayifyAggregateCannotReenterParty() {
        let group = OutputGroup(id: UUID(), name: "Everywhere", deviceIDs: ["private-aggregate", "speaker"])
        let live = [
            OutputDevice(id: "private-aggregate", name: "Airplayify Local Outputs", kind: .builtIn),
            OutputDevice(id: "speaker", name: "MacBook Pro Speakers", kind: .builtIn)
        ]

        let plan = PartyOutputPlan(group: group, liveDevices: live)

        XCTAssertEqual(plan.localDevices.map(\.name), ["MacBook Pro Speakers"])
    }

    func testOfflineMembersRemainVisible() {
        let group = OutputGroup(id: UUID(), name: "Party", deviceIDs: ["offline"])
        let plan = PartyOutputPlan(group: group, liveDevices: [])
        XCTAssertEqual(plan.unavailableDevices.map(\.name), ["offline"])
    }

    func testKnownUnavailableLiveMemberIsDegraded() {
        let group = OutputGroup(id: UUID(), name: "Party", deviceIDs: ["roku"])
        let plan = PartyOutputPlan(group: group, liveDevices: [OutputDevice(id: "roku", name: "Roku", kind: .airPlay, isAvailable: false)])
        XCTAssertEqual(plan.unavailableDevices.map(\.name), ["Roku"])
    }
}
