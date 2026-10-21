import AppKit
import SwiftUI

/// A borderless, non-activating Liquid Glass panel. It never becomes key, so
/// the app you're typing in keeps focus — all keyboard input reaches the panel
/// through the event tap instead. Built once at launch and only re-shown, so
/// opening it is just a reposition + order-front.
@MainActor
final class PanelController {
    private let panel: NSPanel
    /// Whether the panel hangs below its anchor (so resizes keep the top edge
    /// fixed) or sits above it (keep the bottom edge fixed).
    private var hangsBelow = true

    init(model: PanelModel, actions: PanelActions) {
        let size = PanelMetrics.size(compact: false)
        panel = GlassPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.animationBehavior = .none

        let hosting = FirstMouseHostingView(rootView: PanelView(model: model, actions: actions))
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]

        let glass = NSGlassEffectView(frame: NSRect(origin: .zero, size: size))
        glass.cornerRadius = PanelMetrics.cornerRadius
        glass.style = .regular
        glass.autoresizingMask = [.width, .height]
        glass.contentView = hosting
        panel.contentView = glass
    }

    var isVisible: Bool { panel.isVisible }

    /// Shows the panel hanging just below `anchor` (the caret), flipping above
    /// it when there's no room, and clamped to the visible screen area.
    func show(near anchor: NSRect, compact: Bool) {
        let screen = NSScreen.screens.first { $0.frame.contains(anchor.origin) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = PanelMetrics.size(compact: compact)
        // Decide the side using the full height so expanding never needs a flip.
        let fullHeight = PanelMetrics.fullHeight
        let gap: CGFloat = 8

        hangsBelow = anchor.minY - gap - fullHeight >= visible.minY
        var origin = NSPoint(
            x: anchor.minX - 18,
            y: hangsBelow ? anchor.minY - gap - size.height : anchor.maxY + gap
        )
        origin.x = min(max(origin.x, visible.minX + gap), visible.maxX - size.width - gap)
        origin.y = min(max(origin.y, visible.minY + gap), visible.maxY - size.height - gap)

        present(NSRect(origin: origin, size: size))
    }

    func showCentered() {
        guard let visible = NSScreen.main?.visibleFrame else { return }
        let size = PanelMetrics.size(compact: false)
        hangsBelow = true
        present(NSRect(origin: NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2 + 80),
                       size: size))
    }

    /// Switches between the compact save card and the full list in place.
    func setCompact(_ compact: Bool) {
        let size = PanelMetrics.size(compact: compact)
        guard panel.isVisible, panel.frame.size != size else { return }
        var frame = panel.frame
        if hangsBelow { frame.origin.y = frame.maxY - size.height }
        frame.size = size
        panel.setFrame(frame, display: true)
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func present(_ frame: NSRect) {
        panel.setFrame(frame, display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.08
            panel.animator().alphaValue = 1
        }
    }
}

private final class GlassPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Lets a click on the panel act immediately instead of first "activating" it.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
