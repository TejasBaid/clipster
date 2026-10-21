import AppKit
import ClipsterCore

/// Glue between the event tap, the gesture state machine, the store and the
/// panel. Every keyboard event flows through `handle(_:)`.
@MainActor
final class Coordinator {
    /// How long ⌘C / ⌘V must be held before it counts as a hold.
    static let holdThreshold: Duration = .milliseconds(350)

    private let store: ClipStore
    private let watcher: PasteboardWatcher
    private let model: PanelModel
    private var panel: PanelController!
    private var tap: EventTap!
    private var machine = HotkeyMachine()
    private var holdTimer: Task<Void, Never>?

    init(store: ClipStore, watcher: PasteboardWatcher) {
        self.store = store
        self.watcher = watcher
        self.model = PanelModel(store: store)
        self.panel = PanelController(model: model, actions: makeActions())
        self.tap = EventTap { [unowned self] in self.handle($0) }

        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
    }

    var isTapRunning: Bool { tap.isRunning }

    @discardableResult
    func startTap() -> Bool { tap.start() }

    /// Opens the panel without the gesture (menu bar, `--preview`).
    func showSticky(centered: Bool = false) {
        watcher.poll()
        model.reset(mode: .paste)
        machine.openSticky(.paste)
        sync()
        centered ? panel.showCentered() : panel.show(near: CaretLocator.anchor(), compact: false)
    }

    func dismiss() {
        guard panel.isVisible || machine.phase != .idle else { return }
        cancelHoldTimer()
        machine.dismiss()
        panel.hide()
        sync()
    }

    // MARK: - Keyboard

    private func handle(_ event: HotkeyMachine.Event) -> Bool {
        let output = machine.handle(event)
        output.effects.forEach(perform)
        sync()
        return output.swallow
    }

    private func sync() {
        if let mode = machine.mode, mode != model.mode { model.mode = mode }
        if model.isHolding != machine.isHolding { model.isHolding = machine.isHolding }
        panel.setCompact(model.isCompact)
    }

    private func perform(_ effect: HotkeyMachine.Effect) {
        switch effect {
        case .startHoldTimer:
            cancelHoldTimer()
            holdTimer = Task { [weak self] in
                try? await Task.sleep(for: Self.holdThreshold)
                guard !Task.isCancelled else { return }
                _ = self?.handle(.holdTimerFired)
            }
        case .cancelHoldTimer:
            cancelHoldTimer()
        case .open(let mode):
            watcher.poll()   // make sure the copy that just happened is on top
            model.reset(mode: mode)
            sync()
            panel.show(near: CaretLocator.anchor(), compact: model.isCompact)
        case .close:
            panel.hide()
        case .sendPaste:
            Paster.sendPaste()
        case .saveSelectedToSlot(let n):
            watcher.poll()
            saveToSlot(model.selectedClip, n)
        case .pasteSlot(let n):
            if let clip = store.slot(n) { Paster.paste(clip.text) } else { NSSound.beep() }
        case .pasteSelected:
            if let clip = model.selectedClip { Paster.paste(clip.text) }
        case .moveSelection(let delta):
            model.move(delta)
        case .appendQuery(let text):
            model.query += text
        case .deleteQueryChar:
            if !model.query.isEmpty { model.query.removeLast() }
        case .deleteSelected:
            switch model.selectedRow {
            case .slot(let n, _)?: store.clearSlot(n)
            case .history(let clip)?: store.remove(id: clip.id)
            case nil: return
            }
            model.selection = min(model.selection, max(model.rows.count - 1, 0))
        }
    }

    private func cancelHoldTimer() {
        holdTimer?.cancel()
        holdTimer = nil
    }

    private func saveToSlot(_ clip: Clip?, _ n: Int) {
        guard let clip else { NSSound.beep(); return }
        store.assign(clip, toSlot: n)
        model.flash(n)
    }

    // MARK: - Mouse

    private func makeActions() -> PanelActions {
        PanelActions(
            pick: { [unowned self] clip in
                dismiss()
                Paster.paste(clip.text)
            },
            tapSlot: { [unowned self] n in
                if model.mode == .copy {
                    saveToSlot(model.selectedClip, n)
                } else if let clip = store.slot(n) {
                    dismiss()
                    Paster.paste(clip.text)
                }
            },
            clearSlot: { [unowned self] n in store.clearSlot(n) },
            saveToSlot: { [unowned self] clip, n in saveToSlot(clip, n) },
            delete: { [unowned self] clip in store.remove(id: clip.id) }
        )
    }
}
