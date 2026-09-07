import AppKit
import CoreGraphics
import Foundation
import ApplicationServices

enum SetupAccess {
    static let bundleIdentifier = Bundle.main.bundleIdentifier ?? "unknown"
    static let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
    static let blackHoleInstallCommand = "brew install --cask blackhole-2ch"
    static let preferVirtualAudioKey = "preferVirtualAudioOutput"
    static let automaticallyRefreshOutputsKey = "automaticallyRefreshOutputs"
    static let masterVolumeKey = "masterVolume"
    static let outputVolumesKey = "outputVolumes"
    static let captureVolumeKeysKey = "captureVolumeKeys"
    static let didMigrateToBlackHoleDefaultKey = "didMigrateToBlackHoleDefault"

    static var screenCaptureAllowed: Bool {
        CGPreflightScreenCaptureAccess()
    }

    static var accessibilityAllowed: Bool {
        #if APP_STORE
        false
        #else
        AXIsProcessTrusted()
        #endif
    }

    @discardableResult
    static func requestAccessibilityAccess() -> Bool {
        #if APP_STORE
        return false
        #else
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
        #endif
    }

    static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    static var virtualAudioDriverName: String? {
        AudioDeviceCatalog.devices()
            .first(where: { $0.name.localizedCaseInsensitiveContains("BlackHole") })?
            .name
    }

    static var virtualAudioDriverInstalled: Bool {
        FileManager.default.fileExists(atPath: "/Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver")
    }

    static var virtualAudioAvailable: Bool {
        virtualAudioDriverName != nil
    }

    static func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    static func restartApplication() {
        let appPath = Bundle.main.bundleURL.path
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sh")
        child.arguments = ["-c", "sleep 0.8; /usr/bin/open -n \"$1\"", "airplayify-restart", appPath]
        try? child.run()
        NSApplication.shared.terminate(nil)
    }

    static func openBlackHoleInstaller() {
        let installer = RuntimePaths.resource("scripts/install-blackhole.command")
        if FileManager.default.fileExists(atPath: installer.path) {
            NSWorkspace.shared.open(installer)
        } else if let url = URL(string: "https://github.com/ExistentialAudio/BlackHole") {
            NSWorkspace.shared.open(url)
        }
    }

    static func copyBlackHoleInstallCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(blackHoleInstallCommand, forType: .string)
    }

    static func diagnosePermissions(includeHelperProbe: Bool = false) {
        let helper = RuntimePaths.resource("SpotifyCapture").path
        let helperExists = FileManager.default.isExecutableFile(atPath: helper)
        var signing = "unsigned"
        var cdhash = "unknown"
        if helperExists {
            let task = Process()
            let pipe = Pipe()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            task.arguments = ["-dv", "--verbose=4", helper]
            task.standardOutput = pipe
            task.standardError = pipe
            try? task.run()
            task.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if let line = output.split(separator: "\n").first(where: { $0.contains("Signature=") }) {
                signing = String(line).replacingOccurrences(of: "Signature=", with: "").trimmingCharacters(in: .whitespaces)
            } else if output.contains("Signature size=") {
                signing = "signed"
            }
            if let line = output.split(separator: "\n").first(where: { $0.contains("CDHash=") }) {
                cdhash = String(line).replacingOccurrences(of: "CDHash=", with: "").trimmingCharacters(in: .whitespaces)
            }
        }

        print("bundle-path=\(Bundle.main.bundleURL.path)")
        print("bundle-identifier=\(bundleIdentifier)")
        print("build-number=\(buildNumber)")
        print("code-signing=\(signing)")
        print("cdhash=\(cdhash)")
        print("cgpreflight-screen-capture=\(screenCaptureAllowed ? "allowed" : "denied")")
        print("ax-trusted=\(accessibilityAllowed ? "allowed" : "denied")")
        print("blackhole-installed=\(virtualAudioDriverInstalled ? "yes" : "no")")
        print("blackhole-loaded=\(virtualAudioDriverName ?? "none")")
        print("prefer-virtual-audio=\(UserDefaults.standard.bool(forKey: preferVirtualAudioKey))")
        print("helper-path=\(helper)")
        print("helper-exists=\(helperExists ? "yes" : "no")")
        let captureState: CaptureAuthorizationState = screenCaptureAllowed ? .spotifyNotRunning : .denied
        print("capture-state=\(captureState)")
        if includeHelperProbe && helperExists {
            let task = Process()
            let pipe = Pipe()
            task.executableURL = URL(fileURLWithPath: helper)
            task.arguments = ["--probe-permission"]
            task.standardOutput = pipe
            task.standardError = FileHandle.nullDevice
            do {
                try task.run()
                let deadline = Date().addingTimeInterval(5)
                while task.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
                if task.isRunning {
                    task.terminate()
                    print("helper-probe=timed-out")
                } else {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let line = String(data: data, encoding: .utf8)?.split(separator: "\n").first.map(String.init) ?? ""
                    print("helper-probe-exit=\(task.terminationStatus)")
                    print("helper-probe-output=\(line)")
                }
            } catch {
                print("helper-probe=launch-failed: \(error.localizedDescription)")
            }
        } else if includeHelperProbe {
            print("helper-probe=helper-missing")
        }
    }
}
