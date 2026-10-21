import Observation
import ClipsterCore

/// UI state for the glass panel. The `HotkeyMachine` owns gesture state; this
/// owns what's on screen (query, selection, flashes).
@MainActor
@Observable
final class PanelModel {
    enum Row: Identifiable {
        case slot(Int, Clip)
        case history(Clip)

        var id: String {
            switch self {
            case .slot(let n, _): "slot-\(n)"
            case .history(let clip): clip.id.uuidString
            }
        }

        var clip: Clip {
            switch self {
            case .slot(_, let clip), .history(let clip): clip
            }
        }

        var slot: Int? {
            if case .slot(let n, _) = self { n } else { nil }
        }
    }

    let store: ClipStore
    var mode: HotkeyMachine.Mode = .paste { didSet { if oldValue != mode { selection = 0 } } }
    var isHolding = false
    var query = "" { didSet { selection = 0 } }
    var selection = 0
    var flashedSlot: Int?

    init(store: ClipStore) {
        self.store = store
    }

    /// Holding ⌘C shows just the "save what you copied" card.
    var isCompact: Bool { mode == .copy && isHolding }

    /// Paste mode lists filled slots first, then history. Save mode lists
    /// history only — the slot keys at the bottom are the targets.
    var rows: [Row] {
        let history = store.search(query).map(Row.history)
        guard mode == .paste else { return history }
        let slots = (1...ClipStore.slotCount).compactMap { n -> Row? in
            guard let clip = store.slot(n),
                  query.isEmpty || clip.text.localizedCaseInsensitiveContains(query) else { return nil }
            return .slot(n, clip)
        }
        return slots + history
    }

    var selectedRow: Row? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    var selectedClip: Clip? { selectedRow?.clip }

    func reset(mode: HotkeyMachine.Mode) {
        self.mode = mode
        query = ""
        selection = 0
        flashedSlot = nil
    }

    /// Wraps around, so repeatedly tapping V while holding ⌘ cycles forever.
    func move(_ delta: Int) {
        let count = rows.count
        guard count > 0 else { return }
        selection = ((selection + delta) % count + count) % count
    }

    func flash(_ slot: Int) {
        flashedSlot = slot
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            if flashedSlot == slot { flashedSlot = nil }
        }
    }
}

/// Mouse interactions from the panel, routed back to the coordinator.
struct PanelActions {
    var pick: (Clip) -> Void
    var tapSlot: (Int) -> Void
    var clearSlot: (Int) -> Void
    var saveToSlot: (Clip, Int) -> Void
    var delete: (Clip) -> Void
}
