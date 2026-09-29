import SwiftUI

struct KeePassList: View {
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
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.xs)
                .padding(.bottom, Theme.Spacing.md)
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
    let entry: KeePassEntry
    let selected: Bool
    let pinned: Bool
    @State private var hovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            SymbolImage(name: pinned ? "star.fill" : "key", size: Theme.Size.menuIcon)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
            Text(entry.title).font(Theme.Typography.rowTitle).lineLimit(1)
            Text(entry.username)
                .font(Theme.Typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
            Spacer(minLength: Theme.Spacing.md)
            if !entry.totp.isEmpty {
                SymbolImage(name: "clock", size: Theme.Size.menuIcon)
                    .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
                    .accessibilityLabel("One-time code available")
            }
            Text(entry.group)
                .font(Theme.Typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textTertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(selected ? Theme.Colors.selection : hovered ? Theme.Colors.rowHover : .clear))
        .armedHover($hovered)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .accessibilityHint("Paste password. Open Actions for more options.")
    }
}
