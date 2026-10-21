import AppKit

/// Writes to the pasteboard and synthesizes ⌘V into the frontmost app.
enum Paster {
    /// Stamped on our synthetic events so the event tap lets them through.
    static let marker: Int64 = 0x434C_4950  // "CLIP"

    static func write(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    static func sendPaste() {
        let source = CGEventSource(stateID: .hidSystemState)
        source?.userData = marker
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: keyDown) else { continue }
            event.flags = .maskCommand
            event.setIntegerValueField(.eventSourceUserData, value: marker)
            event.post(tap: .cghidEventTap)
        }
    }

    static func paste(_ text: String) {
        write(text)
        sendPaste()
    }
}
