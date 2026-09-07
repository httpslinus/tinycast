import SwiftUI

struct KeePassAutoLockSettingsView: View {
    @Environment(KeePassCoordinator.self) private var coordinator
    @FocusState private var focusedOption: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            Text("Lock after inactivity")
                .font(Theme.Typography.sectionHeader)
                .foregroundStyle(Theme.Colors.textSecondary)
            VStack(spacing: 0) {
                ForEach(KeePassAutoLock.presets + [0], id: \.self) { seconds in
                    KeePassAutoLockOption(
                        title: KeePassAutoLock.title(seconds: seconds == 0 ? nil : seconds),
                        selected: coordinator.store.autoLockSeconds == (seconds == 0 ? nil : seconds)
                    ) {
                        coordinator.setAutoLock(seconds: seconds == 0 ? nil : seconds)
                        coordinator.closeAutoLockSettings()
                    }
                    .focused($focusedOption, equals: seconds)
                }
            }
            Text("Sleep and screen lock always lock the database.")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .frame(maxWidth: Theme.Size.dialogWidth)
        .padding(Theme.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { focusedOption = coordinator.store.autoLockSeconds ?? 0 }
    }
}

private struct KeePassAutoLockOption: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(Theme.Typography.rowTitle)
                Spacer()
                SymbolImage(name: "checkmark", size: Theme.Size.menuIcon)
                    .opacity(selected ? 1 : 0)
            }
            .padding(Theme.Spacing.md)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(hovered ? Theme.Colors.rowHover : .clear))
        }
        .buttonStyle(.plain)
        .armedHover($hovered)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
