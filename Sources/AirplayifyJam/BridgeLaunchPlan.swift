import Foundation

struct BridgeLaunchPlan: Equatable, Sendable {
    enum CaptureMode: Equatable, Sendable {
        case screenCapture
        case virtualAudio
    }

    let executableURL: URL
    let arguments: [String]
    let status: String

    static func make(
        deviceNames: [String],
        captureMode: CaptureMode = .screenCapture
    ) -> Result<BridgeLaunchPlan, BridgeLaunchError> {
        guard !deviceNames.isEmpty else { return .failure(.noAirPlayTargets) }
        let scriptName = captureMode == .virtualAudio
            ? "scripts/spotify-virtual-capture.sh"
            : "scripts/spotify-screen-capture.sh"
        let script = RuntimePaths.resource(scriptName)
        let sourceDescription = captureMode == .virtualAudio ? "virtual audio" : "Spotify"
        return .success(BridgeLaunchPlan(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: [script.path] + deviceNames,
            status: "Streaming \(sourceDescription) to \(deviceNames.count) AirPlay device(s)"
        ))
    }
}

enum BridgeLaunchError: LocalizedError, Equatable {
    case noAirPlayTargets
    case missingPython
    case missingRuntime
    case missingFFmpeg
    case screenCaptureDenied

    var errorDescription: String? {
        switch self {
        case .noAirPlayTargets: return "No AirPlay devices selected"
        case .missingPython: return "Missing .venv; install requirements.txt first"
        case .missingRuntime: return "AirPlay sender runtime is not installed. Open Setup & Help to install it."
        case .missingFFmpeg: return "FFmpeg is required for AirPlay audio encoding."
        case .screenCaptureDenied: return "Screen & system audio access is not allowed. Open Setup & Help to approve it."
        }
    }
}
