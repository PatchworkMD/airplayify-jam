import Foundation
import Combine

@MainActor
final class SpotifyBridge: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var status = "Stopped"
    private var process: Process?
    private var statusFileURL: URL?
    private var startupDeadline: Date?
    private static let startupTimeout: TimeInterval = 15

    var isReady: Bool {
        guard isRunning, let statusFileURL,
              let data = try? Data(contentsOf: statusFileURL),
              let snapshot = SenderStatusSnapshot.decode(data) else { return false }
        return snapshot.state == .ready
    }

    var requiresVirtualAudioRoute: Bool {
        let preference = UserDefaults.standard.object(forKey: SetupAccess.preferVirtualAudioKey) as? Bool
        return Self.shouldUseVirtualAudio(
            preference: preference,
            virtualAudioAvailable: SetupAccess.virtualAudioAvailable,
            screenCaptureAllowed: SetupAccess.screenCaptureAllowed
        )
    }

    func start(deviceNames: [String]) -> Result<Void, BridgeLaunchError> {
        stop()
        let useVirtualAudio = requiresVirtualAudioRoute
        let captureMode: BridgeLaunchPlan.CaptureMode = useVirtualAudio ? .virtualAudio : .screenCapture
        guard let python = AirPlayRuntime.python else {
            status = BridgeLaunchError.missingRuntime.localizedDescription
            return .failure(.missingRuntime)
        }
        guard let ffmpeg = AirPlayRuntime.ffmpeg else {
            status = BridgeLaunchError.missingFFmpeg.localizedDescription
            return .failure(.missingFFmpeg)
        }
        switch BridgeLaunchPlan.make(deviceNames: deviceNames, captureMode: captureMode) {
        case .failure(let error):
            status = error.localizedDescription
            return .failure(error)
        case .success(let launchPlan):
            let child = Process()
            child.executableURL = launchPlan.executableURL
            child.arguments = launchPlan.arguments
            var environment = ProcessInfo.processInfo.environment
            let senderStatusFile = FileManager.default.temporaryDirectory
                .appendingPathComponent("airplayify-sender-\(UUID().uuidString).json")
            try? FileManager.default.removeItem(at: senderStatusFile)
            environment["AIRPLAYIFY_STATUS_FILE"] = senderStatusFile.path
            environment["AIRPLAYIFY_PYTHON"] = python.path
            environment["AIRPLAYIFY_FFMPEG"] = ffmpeg.path
            environment["AIRPLAYIFY_VOLUME"] = String(Int((UserDefaults.standard.object(forKey: SetupAccess.masterVolumeKey) as? Double ?? 1) * 100))
            if let volumes = UserDefaults.standard.dictionary(forKey: SetupAccess.outputVolumesKey),
               let data = try? JSONSerialization.data(withJSONObject: volumes),
               let json = String(data: data, encoding: .utf8) {
                environment["AIRPLAYIFY_VOLUMES_JSON"] = json
            }
            child.environment = environment
            child.standardOutput = FileHandle.standardOutput
            child.standardError = FileHandle.standardError
            child.terminationHandler = { [weak self] process in
                Task { @MainActor in
                    let senderStatus = Self.readStatus(at: senderStatusFile)
                    try? FileManager.default.removeItem(at: senderStatusFile)
                    guard let self, self.process === process else { return }
                    self.process = nil
                    self.statusFileURL = nil
                    self.startupDeadline = nil
                    self.isRunning = false
                    if process.terminationStatus == 0 {
                        self.status = "Stopped"
                    } else if senderStatus?.state == .failed {
                        self.status = senderStatus?.detail ?? "AirPlay sender failed."
                    } else if process.terminationStatus == 78 {
                        self.status = "AirPlay runtime is incomplete. Open Setup & Help to repair it."
                    } else {
                        self.status = "Exited with code \(process.terminationStatus)"
                    }
                }
            }
            do {
                try child.run()
                process = child
                statusFileURL = senderStatusFile
                startupDeadline = Date().addingTimeInterval(Self.startupTimeout)
                isRunning = true
                status = "Connecting to \(deviceNames.count) AirPlay device(s)…"
                return .success(())
            } catch {
                try? FileManager.default.removeItem(at: senderStatusFile)
                status = "Could not start sender: \(error.localizedDescription)"
                return .failure(.missingPython)
            }
        }
    }

    func refreshStatus() {
        guard isRunning else { return }
        if let statusFileURL, let snapshot = Self.readStatus(at: statusFileURL) {
            switch snapshot.state {
            case .starting:
                status = snapshot.detail
            case .ready:
                status = snapshot.detail
                startupDeadline = nil
            case .failed:
                terminate(with: snapshot.detail)
                return
            }
        }
        if let startupDeadline, Date() >= startupDeadline {
            terminate(with: "AirPlay sender startup timed out before the receivers became ready.")
        }
    }

    func stop() {
        terminate(with: "Stopped")
    }

    private func terminate(with finalStatus: String) {
        let child = process
        process = nil
        startupDeadline = nil
        if let statusFileURL { try? FileManager.default.removeItem(at: statusFileURL) }
        statusFileURL = nil
        if child?.isRunning == true { child?.terminate() }
        isRunning = false
        status = finalStatus
    }

    private nonisolated static func readStatus(at url: URL) -> SenderStatusSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return SenderStatusSnapshot.decode(data)
    }

    nonisolated static func shouldUseVirtualAudio(
        preference: Bool?,
        virtualAudioAvailable: Bool,
        screenCaptureAllowed: Bool
    ) -> Bool {
        guard virtualAudioAvailable else { return false }
        if preference == true { return true }
        return !screenCaptureAllowed
    }
}

extension SpotifyBridge: AirPlayBridging {}
