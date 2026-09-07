import XCTest
@testable import AirplayifyJam

final class SpotifyLaneStoreTests: XCTestCase {
    func testProfilesRoundTripAndTokensStayOutOfFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = SpotifyLaneStore(directory: directory)
        let profile = SpotifyProfile(id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!, label: "Primary", clientID: "client", assignedDeviceID: "device-1")

        try store.save([profile])

        let data = try Data(contentsOf: directory.appendingPathComponent("AirplayifyJam/spotify-profiles.json"))
        let decoded = try JSONDecoder().decode([SpotifyProfile].self, from: data)

        XCTAssertEqual(decoded, [profile])
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("accessToken"))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("refreshToken"))
    }

    func testControllerAddRemoveAndAssign() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = SpotifyLaneStore(directory: directory)
        let controller = SpotifyConnectController(store: store, tokenStore: InMemoryTokenStore(tokens: nil), transport: FakeSpotifyTransport(responses: []))
        let profile = SpotifyProfile(id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!, label: "Primary", clientID: "client")

        try controller.add(profile)
        try controller.assign(device: "device-1", to: profile.id)
        XCTAssertEqual(controller.profiles.first?.assignedDeviceID, "device-1")
        try controller.remove(profile.id)
        XCTAssertTrue(controller.profiles.isEmpty)
    }

    func testTransferReportsMissingTokenAndAssignment() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = SpotifyLaneStore(directory: directory)
        let profile = SpotifyProfile(id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!, label: "Primary", clientID: "client")
        let controller = SpotifyConnectController(store: store, tokenStore: InMemoryTokenStore(tokens: nil), transport: FakeSpotifyTransport(responses: []))
        try controller.add(profile)

        let missingAssignment = try controller.transferAssignedPlayback(for: profile.id)
        if case .missingAssignment = missingAssignment.kind {} else { XCTFail("Expected missing assignment") }

        try controller.assign(device: "device-1", to: profile.id)
        let missingToken = try controller.transferAssignedPlayback(for: profile.id)
        if case .missingToken = missingToken.kind {} else { XCTFail("Expected missing token") }
    }
}
