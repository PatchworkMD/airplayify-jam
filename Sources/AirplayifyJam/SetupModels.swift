import Foundation

enum SetupPage: String, CaseIterable, Identifiable {
    case welcome
    case capture
    case outputs
    case spotify
    case test
    case diagnostics

    var id: String { rawValue }
}

enum SetupAction {
    case help
    case gear
    case connectSpotify
    case fixCapture
    case fixOutputs
    case startTest
}

enum SetupRouting {
    static func page(for action: SetupAction) -> SetupPage {
        switch action {
        case .help: .welcome
        case .gear: .diagnostics
        case .connectSpotify: .spotify
        case .fixCapture: .capture
        case .fixOutputs: .outputs
        case .startTest: .test
        }
    }
}

struct SetupOnboardingState: Equatable {
    let isComplete: Bool

    func automaticPage(readiness: JamReadiness) -> SetupPage? {
        guard !isComplete || !readiness.canStart else { return nil }
        return isComplete ? readiness.page : .welcome
    }

    func markingComplete() -> SetupOnboardingState {
        SetupOnboardingState(isComplete: true)
    }
}

enum SetupOnboardingPersistence {
    static let completionKey = "setupOnboardingComplete"
}

@MainActor
protocol SetupPresenting: AnyObject {
    func show(page: SetupPage)
}

enum CaptureAuthorizationState: Equatable {
    case checking
    case notRequested
    case denied
    case restartRequired
    case authorized
    case spotifyNotRunning
    case captureFailed(String)

    var isUsable: Bool {
        switch self {
        case .authorized, .spotifyNotRunning: true
        default: false
        }
    }
}

enum CaptureReadiness {
    static func isReady(
        preferVirtualAudio: Bool,
        virtualAudioAvailable: Bool,
        screenCaptureAllowed: Bool,
        authorization: CaptureAuthorizationState
    ) -> Bool {
        if preferVirtualAudio {
            return virtualAudioAvailable
        }
        return screenCaptureAllowed || authorization.isUsable
    }
}

enum CaptureProbeTrigger: Equatable {
    case automaticMonitor
    case viewAppear
    case appBecameActive
    case outputRefreshButton
    case setupRefreshButton
    case oneClickSetup
    case explicitUserTest

    var mayRunHelperProbe: Bool {
        self == .explicitUserTest
    }
}

struct JamReadiness: Equatable {
    enum Severity: Equatable { case ready, attention, blocked }

    let severity: Severity
    let title: String
    let detail: String
    let page: SetupPage
    let canStart: Bool

    static func evaluate(
        runtimeReady: Bool,
        selectedOutputCount: Int,
        capture: CaptureAuthorizationState,
        party: PartyRuntime.State,
        selectedOutputsAvailable: Bool = true
    ) -> JamReadiness {
        if case .failed(let message) = party {
            return JamReadiness(.blocked, "Needs attention", message, .test, false)
        }
        guard runtimeReady else {
            return JamReadiness(.blocked, "Setup required", "AirPlay sender runtime is incomplete.", .capture, false)
        }
        guard selectedOutputCount > 0 else {
            return JamReadiness(.attention, "Choose an output", "Select at least one available output.", .outputs, false)
        }
        guard selectedOutputsAvailable else {
            return JamReadiness(.attention, "Output unavailable", "Wake or reconnect the selected output, then refresh.", .outputs, false)
        }
        switch capture {
        case .authorized, .spotifyNotRunning:
            return JamReadiness(.ready, "Ready", "Choose outputs and press Start Party.", .test, true)
        case .restartRequired:
            return JamReadiness(.attention, "Restart required", "Restart Airplayify Jam to apply the capture permission.", .capture, false)
        case .notRequested:
            return JamReadiness(.attention, "Setup required", "Allow Screen & System Audio Recording for Airplayify Jam.", .capture, false)
        case .checking:
            return JamReadiness(.attention, "Checking…", "Verifying the capture helper.", .capture, false)
        case .denied:
            return JamReadiness(.blocked, "Needs attention", "Screen & system audio access is not allowed.", .capture, false)
        case .captureFailed(let message):
            return JamReadiness(.blocked, "Capture unavailable", message, .capture, false)
        }
    }

    private init(_ severity: Severity, _ title: String, _ detail: String, _ page: SetupPage, _ canStart: Bool) {
        self.severity = severity
        self.title = title
        self.detail = detail
        self.page = page
        self.canStart = canStart
    }
}
