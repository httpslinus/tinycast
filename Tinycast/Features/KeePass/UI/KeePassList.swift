import SwiftUI

struct KeePassList: View {
    @Environment(\.metrics) private var metrics
    @Environment(KeePassCoordinator.self) private var coordinator
    let entries: [KeePassEntry]
    let selectedID: String?
    let scroll: ScrollIntent
    let onActivate: (KeePassEntry) -> Void
    let onActions: (KeePassEntry) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(entries) { entry in
                        KeePassRow(entry: entry, selected: entry.id == selectedID, pinned: coordinator.store.isPinned(entry))
                            .selectionFrame(entry.id == selectedID)
                            .contentShape(Rectangle())
                            .onTapGesture { onActivate(entry) }
                            .onRightClick { onActions(entry) }
                    }
                }
                .padding(.horizontal, metrics.spacing.md)
                .padding(.top, metrics.spacing.xs)
                .padding(.bottom, metrics.spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            .scrollFollowsSelection(scroll, row: selectedID, atOrigin: selectedID == entries.first?.id, proxy: proxy)
        }
    }
}

private struct KeePassRow: View {
    @Environment(\.metrics) private var metrics
    let entry: KeePassEntry
    let selected: Bool
    let pinned: Bool
    @State private var hovered = false

    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            SymbolImage(name: pinned ? "star.fill" : "key", size: metrics.size.menuIcon)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: metrics.size.rowIcon, height: metrics.size.rowIcon)
            Text(entry.title).font(metrics.typography.rowTitle).lineLimit(1)
            Text(entry.username)
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
            Spacer(minLength: metrics.spacing.md)
            if !entry.totp.isEmpty {
                SymbolImage(name: "clock", size: metrics.size.menuIcon)
                    .frame(width: metrics.size.rowIcon, height: metrics.size.rowIcon)
                    .accessibilityLabel("One-time code available")
            }
            Text(entry.group)
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textTertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                .fill(selected ? Theme.Colors.selection : hovered ? Theme.Colors.rowHover : .clear))
        .armedHover($hovered)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .accessibilityHint("Paste password. Open Actions for more options.")
    }
}
