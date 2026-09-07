import AppKit
import ApplicationServices

struct MediaKeyPolicy: Equatable {
    let takeoverEnabled: Bool
    let party: PartyRuntime.State

    var takesOverVolumeKeys: Bool {
        #if APP_STORE
        return false
        #else
        guard takeoverEnabled else { return false }
        switch party {
        case .running, .degraded: return true
        case .stopped, .starting, .failed: return false
        }
        #endif
    }

    func applying(
        _ command: MediaKeyInterceptor.Command,
        to state: MediaKeyVolumeState
    ) -> MediaKeyVolumeState {
        guard takesOverVolumeKeys else { return state }
        switch command {
        case .volumeUp:
            return MediaKeyVolumeState(
                masterVolume: min(1, state.masterVolume + MediaKeyVolumeState.step),
                lastAudibleVolume: state.lastAudibleVolume
            )
        case .volumeDown:
            return MediaKeyVolumeState(
                masterVolume: max(0, state.masterVolume - MediaKeyVolumeState.step),
                lastAudibleVolume: state.lastAudibleVolume
            )
        case .mute:
            if state.masterVolume > 0 {
                return MediaKeyVolumeState(masterVolume: 0, lastAudibleVolume: state.masterVolume)
            }
            return MediaKeyVolumeState(
                masterVolume: max(state.lastAudibleVolume, 0.25),
                lastAudibleVolume: state.lastAudibleVolume
            )
        }
    }
}

struct MediaKeyVolumeState: Equatable {
    static let step = 0.0625

    let masterVolume: Double
    let lastAudibleVolume: Double
}

final class MediaKeyInterceptor {
    enum Command: Equatable { case volumeUp, volumeDown, mute }

    var handler: ((Command) -> Void)?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    func setEnabled(_ enabled: Bool) {
        if enabled { start() } else { stop() }
    }

    func apply(_ policy: MediaKeyPolicy) {
        setEnabled(policy.takesOverVolumeKeys)
    }

    func start() {
        #if !APP_STORE
        guard eventTap == nil, SetupAccess.accessibilityAllowed else { return }
        let mask = CGEventMask(1) << CGEventType(rawValue: 14)!.rawValue
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: mediaKeyTapCallback,
            userInfo: pointer
        ) else { return }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        #endif
    }

    func stop() {
        #if !APP_STORE
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        runLoopSource = nil
        eventTap = nil
        #endif
    }

    fileprivate func process(_ event: CGEvent) -> Bool {
        guard let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype.rawValue == 8 else { return false }
        guard let command = Self.command(data1: nsEvent.data1, subtype: Int(nsEvent.subtype.rawValue)) else { return false }
        guard let handler else { return false }
        DispatchQueue.main.async { handler(command) }
        return true
    }

    static func command(data1 data: Int, subtype: Int) -> Command? {
        guard subtype == 8 else { return nil }
        let keyCode = (data & 0xFFFF0000) >> 16
        let keyState = (data & 0x0000FF00) >> 8
        guard keyState == 0xA else { return nil }
        switch keyCode {
        case 0: return .volumeUp
        case 1: return .volumeDown
        case 7: return .mute
        default: return nil
        }
    }

    deinit { stop() }
}

#if !APP_STORE
private let mediaKeyTapCallback: CGEventTapCallBack = { proxy, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let interceptor = Unmanaged<MediaKeyInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = interceptor.eventTapForCallback { CGEvent.tapEnable(tap: tap, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    return interceptor.process(event) ? nil : Unmanaged.passUnretained(event)
}

private extension MediaKeyInterceptor {
    var eventTapForCallback: CFMachPort? { eventTap }
}

#endif
