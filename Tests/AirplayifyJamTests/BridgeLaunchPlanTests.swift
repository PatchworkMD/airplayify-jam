import XCTest
@testable import AirplayifyJam

final class BridgeLaunchPlanTests: XCTestCase {
    func testRejectsEmptyTargets() {
        XCTAssertEqual(BridgeLaunchPlan.make(deviceNames: []), .failure(.noAirPlayTargets))
    }

    func testBuildsLaunchArgumentsForSingleTarget() throws {
        let plan = try BridgeLaunchPlan.make(deviceNames: ["Roku Express 4K"]).get()
        XCTAssertEqual(plan.executableURL.path, "/bin/sh")
        XCTAssertEqual(plan.arguments.count, 2)
        XCTAssertTrue(plan.arguments[0].hasSuffix("scripts/spotify-screen-capture.sh"))
        XCTAssertEqual(plan.arguments[1], "Roku Express 4K")
        XCTAssertEqual(plan.status, "Streaming Spotify to 1 AirPlay device(s)")
    }

    func testBuildsLaunchArgumentsForMultipleTargetsWithSpaces() throws {
        let plan = try BridgeLaunchPlan.make(deviceNames: ["50in Hisense Roku TV", "Living Room TV"]).get()
        XCTAssertEqual(plan.arguments.last, "Living Room TV")
        XCTAssertEqual(plan.arguments.dropFirst(), ["50in Hisense Roku TV", "Living Room TV"])
    }

    func testBuildsVirtualAudioLaunchPlan() throws {
        let plan = try BridgeLaunchPlan.make(
            deviceNames: ["Living Room"],
            captureMode: .virtualAudio
        ).get()
        XCTAssertTrue(plan.arguments[0].hasSuffix("scripts/spotify-virtual-capture.sh"))
        XCTAssertEqual(plan.status, "Streaming virtual audio to 1 AirPlay device(s)")
    }

    func testScreenCaptureIsDefaultWhenPermissionIsAllowed() {
        XCTAssertFalse(SpotifyBridge.shouldUseVirtualAudio(
            preference: nil,
            virtualAudioAvailable: true,
            screenCaptureAllowed: true
        ))
    }

    func testBlackHoleIsAutomaticFallbackWhenScreenCaptureIsUnavailable() {
        XCTAssertTrue(SpotifyBridge.shouldUseVirtualAudio(
            preference: nil,
            virtualAudioAvailable: true,
            screenCaptureAllowed: false
        ))
    }
}
