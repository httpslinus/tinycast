import SwiftUI

struct KeePassView: View {
    @Environment(KeePassCoordinator.self) private var coordinator
    @Environment(PaletteState.self) private var palette
    let entries: [KeePassEntry]
    let selection: Int
    let scroll: ScrollIntent
    let onActivate: (KeePassEntry) -> Void
    let onActions: (KeePassEntry) -> Void

    var body: some View {
        Group {
            if coordinator.isShowingAutoLockSettings {
                KeePassAutoLockSettingsView()
            } else if coordinator.isUnlocked {
                if entries.isEmpty {
                    EmptyResults(text: coordinator.entries.isEmpty ? "This database has no entries" : "No matching entries")
                } else {
                    KeePassList(
                        entries: entries, selectedID: entries.indices.contains(selection) ? entries[selection].id : nil,
                        scroll: scroll, onActivate: onActivate, onActions: onActions)
                }
            } else {
                KeePassUnlockView()
            }
        }
        .onChange(of: palette.query) { coordinator.touch() }
        .onChange(of: palette.selection) { coordinator.touch() }
        .onDisappear { coordinator.paletteDidHide() }
    }
}
