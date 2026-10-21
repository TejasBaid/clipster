import Foundation

/// The hold-⌘C / hold-⌘V gesture, as a pure state machine.
///
/// The event tap feeds it raw key events; it answers "swallow this event?"
/// plus a list of effects for the app to perform. Keeping it free of
/// CoreGraphics/AppKit means every gesture rule is unit-testable.
///
/// Gesture summary:
/// - Tap ⌘C / ⌘V: behaves exactly like the system copy / paste.
/// - Hold ⌘C: panel opens. While ⌘ is still down, 1–9 saves the selected
///   (just-copied) item to that slot; releasing ⌘ then closes the panel.
/// - Hold ⌘V: panel opens. While ⌘ is still down, 1–9 pastes that slot
///   immediately; tapping V again (or ↑/↓) cycles history and releasing ⌘
///   pastes the selection, ⌘Tab-style.
/// - Releasing ⌘ without doing anything leaves the panel open ("sticky"):
///   type to search, ↑/↓ + Return to paste, ⌘1–9 for slots, Tab switches
///   between save and paste mode, Esc closes.
public struct HotkeyMachine: Sendable {
    public enum Mode: Sendable, Equatable {
        case copy, paste

        var trigger: Int { self == .copy ? KeyCode.c : KeyCode.v }
        var other: Mode { self == .copy ? .paste : .copy }
    }

    /// What releasing ⌘ does while the panel is held open.
    public enum OnRelease: Sendable, Equatable {
        case stick, close, pasteSelected
    }

    public enum Phase: Sendable, Equatable {
        case idle
        case pending(Mode)                  // trigger down, waiting to see if it's a hold
        case holding(Mode, OnRelease)       // panel open, ⌘ still held
        case sticky(Mode)                   // panel open, ⌘ released
    }

    public enum Effect: Sendable, Equatable {
        case startHoldTimer, cancelHoldTimer
        case open(Mode), close
        case sendPaste                      // replay the ⌘V we held back
        case saveSelectedToSlot(Int)
        case pasteSlot(Int)
        case pasteSelected
        case moveSelection(Int)
        case appendQuery(String), deleteQueryChar
        case deleteSelected
    }

    public struct Output: Sendable, Equatable {
        public var swallow: Bool
        public var effects: [Effect]

        public init(swallow: Bool, _ effects: [Effect] = []) {
            self.swallow = swallow
            self.effects = effects
        }

        static let pass = Output(swallow: false)
        static let swallow = Output(swallow: true)
    }

    public enum Event: Sendable, Equatable {
        case keyDown(code: Int, mods: Modifiers, isRepeat: Bool, chars: String)
        case keyUp(code: Int, mods: Modifiers)
        case flagsChanged(Modifiers)
        case holdTimerFired
    }

    public struct Modifiers: OptionSet, Sendable, Hashable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let command = Modifiers(rawValue: 1 << 0)
        public static let shift = Modifiers(rawValue: 1 << 1)
        public static let option = Modifiers(rawValue: 1 << 2)
        public static let control = Modifiers(rawValue: 1 << 3)
    }

    public private(set) var phase: Phase = .idle

    public init() {}

    public var mode: Mode? {
        switch phase {
        case .idle: nil
        case .pending(let m), .holding(let m, _), .sticky(let m): m
        }
    }

    public var isHolding: Bool {
        if case .holding = phase { true } else { false }
    }

    /// The app closed the panel on its own (click outside, item clicked, …).
    public mutating func dismiss() { phase = .idle }

    /// The panel was opened without the gesture (menu bar item).
    public mutating func openSticky(_ mode: Mode) { phase = .sticky(mode) }

    public mutating func handle(_ event: Event) -> Output {
        switch phase {
        case .idle: idle(event)
        case .pending(let m): pending(m, event)
        case .holding(let m, let onRelease): holding(m, onRelease, event)
        case .sticky(let m): sticky(m, event)
        }
    }

    // MARK: - Phases

    private mutating func idle(_ event: Event) -> Output {
        guard case let .keyDown(code, mods, isRepeat, _) = event, mods == .command, !isRepeat else {
            return .pass
        }
        switch code {
        case KeyCode.c:
            // Let the copy through right away; we only add the panel on hold.
            phase = .pending(.copy)
            return Output(swallow: false, [.startHoldTimer])
        case KeyCode.v:
            // Hold the paste back until we know it's a tap — otherwise a hold
            // would paste twice (once now, once when a slot is chosen).
            phase = .pending(.paste)
            return Output(swallow: true, [.startHoldTimer])
        default:
            return .pass
        }
    }

    private mutating func pending(_ m: Mode, _ event: Event) -> Output {
        let resolveAsTap: [Effect] = m == .paste ? [.cancelHoldTimer, .sendPaste] : [.cancelHoldTimer]
        switch event {
        case .holdTimerFired:
            phase = .holding(m, .stick)
            return Output(swallow: false, [.open(m)])
        case let .keyDown(code, _, isRepeat, _) where code == m.trigger && isRepeat:
            return .swallow
        case let .keyUp(code, _) where code == m.trigger:
            phase = .idle
            return Output(swallow: m == .paste, resolveAsTap)
        case let .flagsChanged(mods) where !mods.contains(.command):
            phase = .idle
            return Output(swallow: false, resolveAsTap)
        case .keyDown:
            // Another key while waiting — it was a tap, get out of the way.
            phase = .idle
            return Output(swallow: false, resolveAsTap)
        default:
            return .pass
        }
    }

    private mutating func holding(_ m: Mode, _ onRelease: OnRelease, _ event: Event) -> Output {
        switch event {
        case let .flagsChanged(mods) where !mods.contains(.command):
            switch onRelease {
            case .stick:
                phase = .sticky(m)
                return .pass
            case .close:
                phase = .idle
                return Output(swallow: false, [.close])
            case .pasteSelected:
                phase = .idle
                return Output(swallow: false, [.close, .pasteSelected])
            }

        case let .keyUp(code, _) where code == m.trigger:
            return Output(swallow: m == .paste)

        case let .keyDown(code, mods, isRepeat, _):
            if code == m.trigger {
                if m == .paste && !isRepeat {
                    phase = .holding(m, .pasteSelected)
                    return Output(swallow: true, [.moveSelection(1)])
                }
                return .swallow
            }
            if let n = KeyCode.digit(code), mods.contains(.command) {
                switch m {
                case .copy:
                    phase = .holding(m, .close)
                    return Output(swallow: true, [.saveSelectedToSlot(n)])
                case .paste:
                    phase = .idle
                    return Output(swallow: true, [.close, .pasteSlot(n)])
                }
            }
            switch code {
            case KeyCode.up, KeyCode.down:
                if m == .paste { phase = .holding(m, .pasteSelected) }
                return Output(swallow: true, [.moveSelection(code == KeyCode.up ? -1 : 1)])
            case KeyCode.escape:
                phase = .idle
                return Output(swallow: true, [.close])
            case KeyCode.return, KeyCode.keypadEnter:
                phase = .idle
                return Output(swallow: true, [.close, .pasteSelected])
            default:
                return closeAndRedispatch(event)
            }

        default:
            return .pass
        }
    }

    private mutating func sticky(_ m: Mode, _ event: Event) -> Output {
        guard case let .keyDown(code, mods, _, chars) = event else { return .pass }

        if mods.contains(.command) {
            if let n = KeyCode.digit(code) {
                switch m {
                case .copy: return Output(swallow: true, [.saveSelectedToSlot(n)])
                case .paste:
                    phase = .idle
                    return Output(swallow: true, [.close, .pasteSlot(n)])
                }
            }
            if code == KeyCode.delete { return Output(swallow: true, [.deleteSelected]) }
            // Any other shortcut (⌘C, ⌘Tab, ⌘Q…) belongs to the frontmost app.
            return closeAndRedispatch(event)
        }

        switch code {
        case KeyCode.escape:
            phase = .idle
            return Output(swallow: true, [.close])
        case KeyCode.return, KeyCode.keypadEnter:
            phase = .idle
            return Output(swallow: true, [.close, .pasteSelected])
        case KeyCode.up:
            return Output(swallow: true, [.moveSelection(-1)])
        case KeyCode.down:
            return Output(swallow: true, [.moveSelection(1)])
        case KeyCode.delete:
            return Output(swallow: true, [.deleteQueryChar])
        case KeyCode.tab:
            phase = .sticky(m.other)
            return .swallow
        default:
            let printable = chars.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
            if !chars.isEmpty && printable && !mods.contains(.control) {
                return Output(swallow: true, [.appendQuery(chars)])
            }
            return .swallow
        }
    }

    /// Close the panel and treat the event as if we were idle, so e.g. ⌘C
    /// pressed while the panel is up still copies (and can arm a new hold).
    private mutating func closeAndRedispatch(_ event: Event) -> Output {
        phase = .idle
        var out = idle(event)
        out.effects.insert(.close, at: 0)
        return out
    }
}

/// macOS virtual key codes (Carbon `kVK_*`), US-ANSI positions.
public enum KeyCode {
    public static let c = 8
    public static let v = 9
    public static let `return` = 36
    public static let tab = 48
    public static let delete = 51
    public static let escape = 53
    public static let keypadEnter = 76
    public static let down = 125
    public static let up = 126

    private static let digits: [Int: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]

    public static func digit(_ code: Int) -> Int? { digits[code] }
}
