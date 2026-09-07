import Foundation

struct CaptureProbeResult: Decodable, Equatable {
    let capture: String
    let spotify: String
    let display: String
}

enum CaptureAuthorizationMapper {
    static func map(exitCode: Int32, result: CaptureProbeResult?, timedOut: Bool = false) -> CaptureAuthorizationState {
        if timedOut { return .captureFailed("The Spotify capture helper timed out.") }
        guard let result else { return .captureFailed("The Spotify capture helper returned no status.") }
        if result.display == "missing" {
            return .captureFailed("No active display is available for Screen & System Audio capture.")
        }
        guard result.capture == "authorized" else { return .denied }
        return result.spotify == "running" ? .authorized : .spotifyNotRunning
    }
}

@MainActor
final class CaptureAuthorizationService {
    private(set) var lastDiagnostic = "Not checked"

    func probe() async -> CaptureAuthorizationState {
        let helper = RuntimePaths.resource("SpotifyCapture")
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            lastDiagnostic = "Spotify capture helper is missing from this build."
            return .captureFailed(lastDiagnostic)
        }

        let result = await Task.detached(priority: .userInitiated) {
            Self.run(helper: helper)
        }.value
        let state = CaptureAuthorizationMapper.map(exitCode: result.exitCode, result: result.probe, timedOut: result.timedOut)
        lastDiagnostic = switch state {
        case .authorized: "Capture helper authorized; Spotify is running."
        case .spotifyNotRunning: "Capture helper authorized; Spotify is not running."
        case .denied: "The capture helper is not authorized in Screen & System Audio Recording."
        case .captureFailed(let message): message
        default: "Capture status is being checked."
        }
        return state
    }

    private struct ProbeExecution: Sendable {
        let exitCode: Int32
        let probe: CaptureProbeResult?
        let timedOut: Bool
    }

    private nonisolated static func run(helper: URL) -> ProbeExecution {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = helper
        process.arguments = ["--probe-permission"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch {
            return ProbeExecution(exitCode: -1, probe: nil, timedOut: false)
        }
        let deadline = Date().addingTimeInterval(5)
        while process.isRunning && Date() < deadline { usleep(20_000) }
        if process.isRunning {
            process.terminate()
            return ProbeExecution(exitCode: -1, probe: nil, timedOut: true)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let line = String(data: data, encoding: .utf8)?.split(separator: "\n").first.map(String.init)
        let probe = line.flatMap { try? JSONDecoder().decode(CaptureProbeResult.self, from: Data($0.utf8)) }
        return ProbeExecution(exitCode: process.terminationStatus, probe: probe, timedOut: false)
    }
}
