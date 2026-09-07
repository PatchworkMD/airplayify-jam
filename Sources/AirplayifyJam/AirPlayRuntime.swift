import Foundation

enum AirPlayRuntime {
    static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Airplayify Jam", isDirectory: true)
    }

    static var managedPython: URL {
        supportDirectory.appendingPathComponent("runtime/bin/python")
    }

    static var python: URL? {
        if let override = ProcessInfo.processInfo.environment["AIRPLAYIFY_PYTHON"] {
            let url = URL(fileURLWithPath: override)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        if FileManager.default.isExecutableFile(atPath: managedPython.path) { return managedPython }
        if Bundle.main.bundleURL.pathExtension != "app" {
            let source = RuntimePaths.sourceRoot.appendingPathComponent(".venv/bin/python")
            if FileManager.default.isExecutableFile(atPath: source.path) { return source }
        }
        return nil
    }

    static var ffmpeg: URL? {
        let candidates = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
        return candidates.map(URL.init(fileURLWithPath:)).first(where: { FileManager.default.isExecutableFile(atPath: $0.path) })
    }

    static var isReady: Bool { python != nil && ffmpeg != nil }
}

@MainActor
final class RuntimeSetupController: ObservableObject {
    @Published private(set) var isInstalling = false
    @Published private(set) var message = ""
    @Published private(set) var isReady = AirPlayRuntime.isReady
    private var process: Process?

    func refresh() {
        isReady = AirPlayRuntime.isReady
        if isReady { message = "AirPlay sender runtime is ready." }
    }

    func install() {
        guard !isInstalling else { return }
        let script = RuntimePaths.resource("scripts/setup-runtime.sh")
        guard FileManager.default.fileExists(atPath: script.path) else {
            message = "Runtime installer is missing from this build."
            return
        }
        isInstalling = true
        message = "Installing the private AirPlay sender runtime…"
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/bash")
        child.arguments = [script.path, AirPlayRuntime.supportDirectory.path, RuntimePaths.resource("requirements.txt").path]
        let pipe = Pipe()
        child.standardOutput = pipe
        child.standardError = pipe
        child.terminationHandler = { [weak self] process in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            Task { @MainActor in
                self?.isInstalling = false
                self?.refresh()
                if process.terminationStatus != 0 {
                    self?.message = output.isEmpty ? "Runtime installation failed (code \(process.terminationStatus))." : output
                }
            }
        }
        do {
            try child.run()
            process = child
        } catch {
            isInstalling = false
            message = "Could not start runtime installer: \(error.localizedDescription)"
        }
    }
}
