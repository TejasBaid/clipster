import Foundation
import Observation

public struct Clip: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let text: String
    /// Single-line, length-capped rendering of `text`, computed once so the UI
    /// never has to touch huge clipboard strings while scrolling.
    public let preview: String
    public var date: Date
    public var sourceApp: String?
    public var sourceBundleID: String?

    public init(text: String, date: Date = .now, sourceApp: String? = nil, sourceBundleID: String? = nil) {
        self.id = UUID()
        self.text = text
        self.preview = Clip.makePreview(text)
        self.date = date
        self.sourceApp = sourceApp
        self.sourceBundleID = sourceBundleID
    }

    static func makePreview(_ text: String) -> String {
        let head = text.prefix(300)
        return head
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

@MainActor
@Observable
public final class ClipStore {
    public static let slotCount = 9

    public private(set) var history: [Clip] = []
    public private(set) var slots: [Clip?] = Array(repeating: nil, count: slotCount)

    public let historyLimit: Int
    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private var pendingSave: DispatchWorkItem?

    /// Pass `fileURL: nil` for an in-memory store (tests, preview mode).
    public init(fileURL: URL?, historyLimit: Int = 300) {
        self.fileURL = fileURL
        self.historyLimit = historyLimit
        load()
    }

    // MARK: History

    public func add(_ text: String, sourceApp: String? = nil, sourceBundleID: String? = nil) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if let i = history.firstIndex(where: { $0.text == text }) {
            // Re-copying something already in history just bumps it to the top.
            var existing = history.remove(at: i)
            existing.date = .now
            history.insert(existing, at: 0)
        } else {
            history.insert(Clip(text: text, sourceApp: sourceApp, sourceBundleID: sourceBundleID), at: 0)
            if history.count > historyLimit { history.removeLast(history.count - historyLimit) }
        }
        scheduleSave()
    }

    public func remove(id: Clip.ID) {
        history.removeAll { $0.id == id }
        scheduleSave()
    }

    public func clearHistory() {
        history.removeAll()
        scheduleSave()
    }

    public func search(_ query: String) -> [Clip] {
        guard !query.isEmpty else { return history }
        return history.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    // MARK: Slots (1-based, matching the ⌘1–9 keys)

    public func slot(_ n: Int) -> Clip? {
        slots.indices.contains(n - 1) ? slots[n - 1] : nil
    }

    public func assign(_ clip: Clip, toSlot n: Int) {
        guard slots.indices.contains(n - 1) else { return }
        slots[n - 1] = clip
        scheduleSave()
    }

    public func clearSlot(_ n: Int) {
        guard slots.indices.contains(n - 1) else { return }
        slots[n - 1] = nil
        scheduleSave()
    }

    public func clearSlots() {
        slots = Array(repeating: nil, count: Self.slotCount)
        scheduleSave()
    }

    // MARK: Persistence

    private struct Snapshot: Codable {
        var history: [Clip]
        var slots: [Clip?]
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        history = Array(snap.history.prefix(historyLimit))
        for (i, clip) in snap.slots.prefix(Self.slotCount).enumerated() { slots[i] = clip }
    }

    private func scheduleSave() {
        guard fileURL != nil else { return }
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.saveNow() } }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75, execute: work)
    }

    public func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        guard let fileURL else { return }
        let snap = Snapshot(history: history, slots: slots)
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(snap).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Clipster: failed to save store: \(error)")
        }
    }
}
