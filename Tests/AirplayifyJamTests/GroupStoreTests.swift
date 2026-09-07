import XCTest
@testable import AirplayifyJam

final class GroupStoreTests: XCTestCase {
    func testGroupsRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = GroupStore(directory: directory)
        let group = OutputGroup(id: UUID(), name: "Everywhere", deviceIDs: ["roku-a", "roku-b"])
        try store.save([group])
        XCTAssertEqual(store.load(), [group])
    }

    func testAirPlayDiscoveryParsesNamesAndDeduplicates() {
        let output = """
        Timestamp     A/R Flags if Domain               Service Type         Instance Name
        20:28:34 Add 3 14 local. _airplay._tcp. 50in Hisense Roku TV
        20:28:34 Add 3 14 local. _airplay._tcp. Roku Express 4K
        20:28:34 Add 3 14 local. _airplay._tcp. 50in Hisense Roku TV
        """
        XCTAssertEqual(AirPlayDiscovery.parse(output).map(\.name), ["50in Hisense Roku TV", "Roku Express 4K"])
    }
}
