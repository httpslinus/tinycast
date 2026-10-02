import SwiftUI

struct KeePassAutoLockSettingsView: View {
    @Environment(\.metrics) private var metrics
    @Environment(KeePassCoordinator.self) private var coordinator
    @FocusState private var focusedOption: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.xl) {
            Text("Lock after inactivity")
                .font(metrics.typography.sectionHeader)
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
        .frame(maxWidth: metrics.size.dialogWidth)
        .padding(metrics.spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: coordinator.formFocusStep) { old, new in
            let options = KeePassAutoLock.presets + [0]
            let current = options.firstIndex(of: focusedOption ?? 0) ?? 0
            let next = (current + (new < old ? -1 : 1) + options.count) % options.count
            focusedOption = options[next]
        }
        .onKeyPress(.return) {
            let seconds = focusedOption ?? coordinator.store.autoLockSeconds ?? 0
            coordinator.setAutoLock(seconds: seconds == 0 ? nil : seconds)
            coordinator.closeAutoLockSettings()
            return .handled
        }
        .task { focusedOption = coordinator.store.autoLockSeconds ?? 0 }
    }
}

private struct KeePassAutoLockOption: View {
    @Environment(\.metrics) private var metrics
    let title: String
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(metrics.typography.rowTitle)
                Spacer()
                SymbolImage(name: "checkmark", size: metrics.size.menuIcon)
                    .opacity(selected ? 1 : 0)
            }
            .padding(metrics.spacing.md)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                .fill(hovered ? Theme.Colors.rowHover : .clear))
        }
        .buttonStyle(.plain)
        .armedHover($hovered)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
