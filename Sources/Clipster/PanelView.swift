import AppKit
import SwiftUI
import ClipsterCore

enum PanelMetrics {
    static let width: CGFloat = 380
    static let fullHeight: CGFloat = 420
    static let compactHeight: CGFloat = 150
    static let cornerRadius: CGFloat = 26

    static func size(compact: Bool) -> CGSize {
        CGSize(width: width, height: compact ? compactHeight : fullHeight)
    }
}

struct PanelView: View {
    @Bindable var model: PanelModel
    let actions: PanelActions

    var body: some View {
        Group {
            if model.isCompact {
                SaveCard(model: model, actions: actions)
            } else {
                browser
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.snappy(duration: 0.2), value: model.flashedSlot)
    }

    private var browser: some View {
        VStack(spacing: 0) {
            SearchBar(query: model.query, isHolding: model.isHolding)
            Hairline()
            ClipList(model: model, actions: actions)
            if model.mode == .copy {
                Hairline()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Save selection to slot")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    SlotKeys(model: model, actions: actions)
                }
                .padding(14)
            }
        }
    }
}

// MARK: - Save card (hold ⌘C)

private struct SaveCard: View {
    let model: PanelModel
    let actions: PanelActions

    var body: some View {
        let clip = model.selectedClip
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                if let saved = model.flashedSlot {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                    Text("Saved to slot \(saved)")
                } else {
                    AppIcon(bundleID: clip?.sourceBundleID, size: 14)
                    Text(clip?.sourceApp.map { "Copied from \($0)" } ?? "Copied")
                }
                Spacer()
            }
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(.secondary)
            .contentTransition(.opacity)

            Text(clip?.preview ?? "Nothing copied yet")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(clip == nil ? .tertiary : .primary)
                .lineLimit(2)
                .padding(.top, 8)

            Spacer(minLength: 12)
            SlotKeys(model: model, actions: actions)
        }
        .padding(16)
    }
}

// MARK: - Search

private struct SearchBar: View {
    let query: String
    let isHolding: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            if query.isEmpty {
                Text(isHolding ? "Release ⌘ to search" : "Search clipboard")
                    .foregroundStyle(.tertiary)
            } else {
                HStack(spacing: 1) {
                    Text(query)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.accentColor)
                        .frame(width: 2, height: 18)
                }
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 16))
        .lineLimit(1)
        .padding(.horizontal, 18)
        .frame(height: 52)
    }
}

// MARK: - List

private struct ClipList: View {
    let model: PanelModel
    let actions: PanelActions

    var body: some View {
        let rows = model.rows
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index == 0 || (row.slot == nil) != (rows[index - 1].slot == nil) {
                            SectionHeader(title: row.slot == nil ? "Recent" : "Slots", isFirst: index == 0)
                        }
                        ClipRow(row: row, selected: index == model.selection)
                            .id(row.id)
                            .onTapGesture { actions.pick(row.clip) }
                            .contextMenu { menu(for: row) }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.never)
            .overlay {
                if rows.isEmpty { EmptyState(searching: !model.query.isEmpty) }
            }
            .onChange(of: model.selection) { _, new in
                guard rows.indices.contains(new) else { return }
                proxy.scrollTo(rows[new].id)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func menu(for row: PanelModel.Row) -> some View {
        if let n = row.slot {
            Button("Clear Slot \(n)") { actions.clearSlot(n) }
        } else {
            Menu("Save to Slot") {
                ForEach(1...ClipStore.slotCount, id: \.self) { n in
                    Button("Slot \(n)") { actions.saveToSlot(row.clip, n) }
                }
            }
            Button("Delete") { actions.delete(row.clip) }
        }
    }
}

private struct SectionHeader: View {
    let title: String
    let isFirst: Bool

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.top, isFirst ? 10 : 14)
            .padding(.bottom, 4)
    }
}

private struct ClipRow: View {
    let row: PanelModel.Row
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            AppIcon(bundleID: row.clip.sourceBundleID, size: 18)
            Text(row.clip.preview)
                .font(.system(size: 13))
                .lineLimit(1)
            Spacer(minLength: 12)
            Text(trailing)
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.primary.opacity(0.09))
            }
        }
        .contentShape(Rectangle())
        .help(String(row.clip.text.prefix(500)))
    }

    private var trailing: String {
        if let n = row.slot { return "⌘\(n)" }
        let seconds = -row.clip.date.timeIntervalSinceNow
        switch seconds {
        case ..<60: return "now"
        case ..<3600: return "\(Int(seconds / 60))m"
        case ..<86_400: return "\(Int(seconds / 3600))h"
        default: return "\(Int(seconds / 86_400))d"
        }
    }
}

private struct EmptyState: View {
    let searching: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: searching ? "magnifyingglass" : "doc.on.clipboard")
                .font(.system(size: 22, weight: .light))
            Text(searching ? "No matches" : "Nothing copied yet")
                .font(.system(size: 12.5))
        }
        .foregroundStyle(.tertiary)
    }
}

// MARK: - Slot keys

/// The nine slots as bare numerals: filled slots are bright, empty ones
/// faint. Saving turns the chosen number accent-colored with an underline.
private struct SlotKeys: View {
    let model: PanelModel
    let actions: PanelActions
    @Namespace private var underline

    var body: some View {
        HStack(spacing: 0) {
            ForEach(1...ClipStore.slotCount, id: \.self) { n in
                key(n, clip: model.store.slot(n), flashed: model.flashedSlot == n)
            }
        }
    }

    private func key(_ n: Int, clip: Clip?, flashed: Bool) -> some View {
        let filled = clip != nil
        return VStack(spacing: 5) {
            Text("\(n)")
                .font(.system(size: 19, weight: filled || flashed ? .medium : .light))
                .foregroundStyle(flashed ? AnyShapeStyle(Color.accentColor)
                                 : filled ? AnyShapeStyle(.primary) : AnyShapeStyle(.primary.opacity(0.22)))
            ZStack {
                if flashed {
                    Capsule()
                        .fill(Color.accentColor)
                        .matchedGeometryEffect(id: "underline", in: underline)
                }
            }
            .frame(width: 14, height: 2.5)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 36)
        .contentShape(Rectangle())
        .onTapGesture { actions.tapSlot(n) }
        .help(clip.map { String($0.text.prefix(300)) } ?? "Empty")
    }
}

// MARK: - Bits

private struct Hairline: View {
    var body: some View {
        Rectangle().fill(.primary.opacity(0.08)).frame(height: 1)
    }
}

/// The source app's icon, falling back to a plain text glyph.
private struct AppIcon: View {
    let bundleID: String?
    let size: CGFloat

    var body: some View {
        if let image = bundleID.flatMap(AppIconCache.icon) {
            Image(nsImage: image)
                .resizable()
                .frame(width: size, height: size)
        } else {
            Image(systemName: "text.alignleft")
                .font(.system(size: size * 0.6, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: size, height: size)
        }
    }
}

@MainActor
private enum AppIconCache {
    private static var icons: [String: NSImage?] = [:]

    static func icon(_ bundleID: String) -> NSImage? {
        if let cached = icons[bundleID] { return cached }
        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
        icons[bundleID] = icon
        return icon
    }
}
