import AppKit
import ApplicationServices

/// Finds the text caret (or selection) of the focused app via Accessibility,
/// in AppKit screen coordinates. Falls back to the mouse when the app doesn't
/// expose it (some Electron/web views don't).
@MainActor
enum CaretLocator {
    private static let systemWide: AXUIElement = {
        let el = AXUIElementCreateSystemWide()
        // Never let a hung app stall the panel.
        AXUIElementSetMessagingTimeout(el, 0.05)
        return el
    }()

    /// Returns the anchor rect the panel should hang off of.
    static func anchor() -> NSRect {
        if let caret = caretRect() { return caret }
        let mouse = NSEvent.mouseLocation
        return NSRect(x: mouse.x, y: mouse.y, width: 0, height: 0)
    }

    private static func caretRect() -> NSRect? {
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement

        var range: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success,
              let range else { return nil }

        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
                element, kAXBoundsForRangeParameterizedAttribute as CFString, range, &boundsValue) == .success,
              let boundsValue, CFGetTypeID(boundsValue) == AXValueGetTypeID() else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect),
              rect.origin != .zero || rect.size != .zero else { return nil }

        // AX uses top-left-origin global coordinates; AppKit uses bottom-left.
        guard let primary = NSScreen.screens.first else { return nil }
        let flipped = NSRect(x: rect.minX, y: primary.frame.maxY - rect.maxY,
                             width: rect.width, height: rect.height)
        // Reject garbage rects that land off every screen.
        guard NSScreen.screens.contains(where: { $0.frame.intersects(flipped.insetBy(dx: -1, dy: -1)) }) else {
            return nil
        }
        return flipped
    }
}
