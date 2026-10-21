import AppKit
import ClipsterCore

/// A session-level CGEventTap that turns raw key events into
/// `HotkeyMachine.Event`s and lets the handler decide whether to swallow them.
/// Requires Accessibility permission.
@MainActor
final class EventTap {
    typealias Handler = (HotkeyMachine.Event) -> Bool

    private let handler: Handler
    private var machPort: CFMachPort?

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    var isRunning: Bool { machPort != nil }

    @discardableResult
    func start() -> Bool {
        guard machPort == nil else { return true }
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        machPort = port
        return true
    }

    fileprivate func process(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS disables slow taps; just turn it back on.
            if let machPort { CGEvent.tapEnable(tap: machPort, enable: true) }
            return false
        default:
            break
        }
        if event.getIntegerValueField(.eventSourceUserData) == Paster.marker { return false }

        let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let mods = Self.modifiers(event.flags)
        switch type {
        case .keyDown:
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            return handler(.keyDown(code: code, mods: mods, isRepeat: isRepeat, chars: Self.characters(event)))
        case .keyUp:
            return handler(.keyUp(code: code, mods: mods))
        case .flagsChanged:
            return handler(.flagsChanged(mods))
        default:
            return false
        }
    }

    private static func modifiers(_ flags: CGEventFlags) -> HotkeyMachine.Modifiers {
        var mods: HotkeyMachine.Modifiers = []
        if flags.contains(.maskCommand) { mods.insert(.command) }
        if flags.contains(.maskShift) { mods.insert(.shift) }
        if flags.contains(.maskAlternate) { mods.insert(.option) }
        if flags.contains(.maskControl) { mods.insert(.control) }
        return mods
    }

    private static func characters(_ event: CGEvent) -> String {
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: buffer.count, actualStringLength: &length, unicodeString: &buffer)
        return String(utf16CodeUnits: buffer, count: length)
    }
}

private func eventTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    // The tap's run loop source lives on the main run loop, so this callback
    // is already on the main thread; the event never leaves it.
    nonisolated(unsafe) let event = event
    nonisolated(unsafe) let pointer = refcon
    let swallow = MainActor.assumeIsolated {
        Unmanaged<EventTap>.fromOpaque(pointer).takeUnretainedValue().process(type, event)
    }
    return swallow ? nil : Unmanaged.passUnretained(event)
}
