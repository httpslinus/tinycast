import SwiftUI

struct KeePassSettingsView: View {
    @Environment(KeePassCoordinator.self) private var coordinator

    var body: some View {
        Form {
            Section {
                SettingsRow(title: "Search KeePass", anchor: .keepassGlobalShortcuts) {
                    ShortcutRecorder(action: .command(.searchKeePass))
                }
            } header: {
                SettingsSectionHeader(.keepassGlobalShortcuts)
            }
            Section {
                fileRow(path: coordinator.store.databasePath, keyFile: false) {
                    SettingsRowTitle(.keepassDatabase, "Database")
                }
                fileRow(path: coordinator.store.keyFilePath, keyFile: true) {
                    SettingsRowTitle(.keepassDatabase, "Key File")
                }
                    .disabled(coordinator.store.databasePath.isEmpty)
            } header: {
                SettingsSectionHeader(.keepassDatabase)
            } footer: {
                Text("Requires KeePassXC. Changing either file locks the database.")
            }
            Section {
                Picker(selection: autoLock) {
                    ForEach(KeePassAutoLock.presets + [0], id: \.self) { seconds in
                        Text(KeePassAutoLock.title(seconds: seconds == 0 ? nil : seconds)).tag(seconds)
                    }
                } label: {
                    SettingsRowTitle(.keepassSecurity, "Auto-lock")
                }
                LabeledContent("Status", value: coordinator.isUnlocked ? "Unlocked" : "Locked")
                if coordinator.isUnlocked {
                    Button("Lock Database", action: coordinator.lock)
                }
            } header: {
                SettingsSectionHeader(.keepassSecurity)
            } footer: {
                Text("Sleep and screen lock always lock the database. Copied values clear after 30 seconds.")
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.keepass)
    }

    private var autoLock: Binding<Int> {
        Binding(get: { coordinator.store.autoLockSeconds ?? 0 }, set: {
            coordinator.setAutoLock(seconds: $0 == 0 ? nil : $0)
        })
    }

    private func fileRow(path: String, keyFile: Bool, @ViewBuilder label: () -> some View) -> some View {
        LabeledContent {
            HStack(spacing: Theme.Spacing.md) {
                Text(path.isEmpty ? (keyFile ? "None" : "Not selected") : URL(fileURLWithPath: path).lastPathComponent)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(path)
                if keyFile, !path.isEmpty {
                    Button("Remove", action: coordinator.removeKeyFile)
                }
                Button(path.isEmpty ? "Choose…" : "Change…") {
                    coordinator.pickFile(keyFile: keyFile, returnToPalette: false)
                }
            }
        } label: {
            label()
        }
    }
}
