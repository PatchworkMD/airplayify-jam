import XCTest
@testable import AirplayifyJam

final class LocalOutputSelectionTests: XCTestCase {
    func testSelectsOnlyLocalOutputs() {
        let selection = LocalOutputSelection(devices: [
            OutputDevice(id: "tv", name: "LG TV", kind: .hdmi),
            OutputDevice(id: "usb", name: "Volt 276", kind: .usb),
            OutputDevice(id: "airplay", name: "Kitchen AirPlay", kind: .airPlay),
            OutputDevice(id: "virtual", name: "Airplayify Multi-Output Device", kind: .virtual)
        ])

        XCTAssertEqual(selection.localDevices.map(\.name), ["LG TV", "Volt 276"])
        XCTAssertEqual(selection.excludedDevices.map(\.name), ["Kitchen AirPlay", "Airplayify Multi-Output Device"])
    }

    func testExcludesMacBookReceiverLoop() {
        let selection = LocalOutputSelection(devices: [
            OutputDevice(id: "macbook", name: "Austin MacBook AirPlay Receiver", kind: .airPlay)
        ])

        XCTAssertTrue(selection.localDevices.isEmpty)
    }
}
