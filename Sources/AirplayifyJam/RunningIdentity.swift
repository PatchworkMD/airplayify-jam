import Foundation
import Security

struct RunningIdentity: Equatable {
    static let canonicalBundleURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Applications/Airplayify Jam.app")

    let bundleURL: URL
    let bundleIdentifier: String
    let shortVersion: String
    let buildNumber: String
    let teamIdentifier: String?

    static var current: RunningIdentity {
        from(bundle: .main, teamIdentifier: currentTeamIdentifier())
    }

    static func from(bundle: Bundle, teamIdentifier: String? = nil) -> RunningIdentity {
        RunningIdentity(
            bundleURL: bundle.bundleURL.standardizedFileURL,
            bundleIdentifier: bundle.bundleIdentifier ?? "unknown",
            shortVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            buildNumber: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            teamIdentifier: teamIdentifier
        )
    }

    static func conflicts(canonical: RunningIdentity, candidate: RunningIdentity) -> Bool {
        canonical.bundleIdentifier == candidate.bundleIdentifier
            && canonical.bundleURL.standardizedFileURL != candidate.bundleURL.standardizedFileURL
    }

    var diagnosticSummary: String {
        let team = teamIdentifier ?? "ad-hoc"
        return "\(bundleURL.path) · \(bundleIdentifier) · \(shortVersion) (\(buildNumber)) · team \(team)"
    }

    private static func currentTeamIdentifier() -> String? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let dictionary = information as? [String: Any] else { return nil }
        return dictionary[kSecCodeInfoTeamIdentifier as String] as? String
    }
}
