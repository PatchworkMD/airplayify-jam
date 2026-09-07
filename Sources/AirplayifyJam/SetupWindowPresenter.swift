import AppKit
import SwiftUI

@MainActor
final class SetupNavigation: ObservableObject {
    @Published var page: SetupPage

    init(page: SetupPage = .welcome) {
        self.page = page
    }
}

@MainActor
final class SetupWindowPresenter: NSObject, SetupPresenting, NSWindowDelegate {
    private let controller: JamController
    private let defaults: UserDefaults
    private let navigation = SetupNavigation()
    private var windowController: NSWindowController?

    init(controller: JamController, defaults: UserDefaults = .standard) {
        self.controller = controller
        self.defaults = defaults
        super.init()
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.controller.refreshOutputs()
            self.showOnboardingIfNeeded()
        }
    }

    func show(page: SetupPage) {
        navigation.page = page
        let windowController = windowController ?? makeWindowController()
        self.windowController = windowController
        NSApp.activate(ignoringOtherApps: true)
        windowController.showWindow(nil)
        windowController.window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        windowController = nil
    }

    func showOnboardingIfNeeded() {
        let state = SetupOnboardingState(
            isComplete: defaults.bool(forKey: SetupOnboardingPersistence.completionKey)
        )
        guard let page = state.automaticPage(readiness: controller.readiness) else { return }
        show(page: page)
    }

    private func makeWindowController() -> NSWindowController {
        let hostingController = NSHostingController(
            rootView: SpotifyConnectSetupView(controller: controller, navigation: navigation)
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Airplayify Jam Setup"
        window.setContentSize(NSSize(width: 680, height: 720))
        window.minSize = NSSize(width: 680, height: 700)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        return NSWindowController(window: window)
    }
}
