import SwiftUI

struct KeePassUnlockView: View {
    @Environment(KeePassCoordinator.self) private var coordinator
    @Environment(PaletteState.self) private var palette
    @FocusState private var passwordFocused: Bool

    private var hasDatabase: Bool { !coordinator.store.databasePath.isEmpty }

    var body: some View {
        @Bindable var coordinator = coordinator
        VStack(spacing: Theme.Spacing.xxl) {
            SymbolImage(name: "lock.shield", size: Theme.Size.dialogIcon)
                .foregroundStyle(Theme.Colors.textTertiary)
            if hasDatabase {
                Text(URL(fileURLWithPath: coordinator.store.databasePath).lastPathComponent)
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(coordinator.store.databasePath)
                SecureField("Database password", text: $coordinator.password)
                    .textFieldStyle(.plain)
                    .padding(Theme.Spacing.xl)
                    .background(Theme.Colors.controlSurface, in: RoundedRectangle(
                        cornerRadius: Theme.Radius.row, style: .continuous))
                    .focused($passwordFocused)
                    .onSubmit(coordinator.unlock)
                    .disabled(coordinator.isLoading)
                    .accessibilityLabel("Database password")
                if !coordinator.store.keyFilePath.isEmpty {
                    Text(URL(fileURLWithPath: coordinator.store.keyFilePath).lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(coordinator.store.keyFilePath)
                }
            } else {
                Text("Choose a KeePass database")
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            if coordinator.isLoading { ProgressView().controlSize(.small) }
            if let failure = coordinator.failure {
                Text(failure)
                    .font(.callout)
                    .foregroundStyle(Theme.Colors.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: Theme.Size.dialogWidth)
        .padding(Theme.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: palette.focusToken) {
            passwordFocused = false
            await Task.yield()
            guard !Task.isCancelled else { return }
            passwordFocused = hasDatabase
        }
    }
}
