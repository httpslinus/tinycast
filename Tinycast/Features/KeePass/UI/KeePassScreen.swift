import SwiftUI

struct KeePassScreen: PaletteScreen {
    let coordinator: KeePassCoordinator
    let vm: PaletteState
    let openActions: () -> Void

    var rows: [KeePassEntry] { coordinator.isShowingForm ? [] : coordinator.results(query: vm.query) }
    var primaryActionTitle: String {
        if coordinator.isLoading { return "Cancel" }
        if !coordinator.isUnlocked {
            return coordinator.store.databasePath.isEmpty ? "Choose Database" : "Unlock"
        }
        return rows.isEmpty ? "Lock Database" : "Paste Password"
    }
    var actsWithoutRows: Bool { !coordinator.isShowingAutoLockSettings }
    var hidesSearchField: Bool { coordinator.isShowingForm }

    func hasPrimaryAction(at selection: Int) -> Bool { !coordinator.isShowingAutoLockSettings }
    func hasActions(at selection: Int) -> Bool { !coordinator.isShowingAutoLockSettings }

    func tab(at selection: Int, backwards: Bool) -> Bool {
        guard coordinator.isShowingForm else { return false }
        coordinator.advanceFormFocus(backwards: backwards)
        return true
    }

    func shiftedPrimary(at selection: Int) -> Bool { pasteUsername(at: selection) }

    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        guard shortcut == .pin, let entry = entry(at: selection) else { return false }
        coordinator.togglePin(entry)
        return true
    }

    private func entry(at selection: Int) -> KeePassEntry? {
        let entries = rows
        return entries.indices.contains(selection) ? entries[selection] : nil
    }

    func activate(at selection: Int) {
        guard !coordinator.isShowingAutoLockSettings else { return }
        if !coordinator.isUnlocked {
            if coordinator.isLoading { coordinator.lock()
            } else if coordinator.store.databasePath.isEmpty { coordinator.pickFile(keyFile: false)
            } else { coordinator.unlock() }
            return
        }
        guard let entry = entry(at: selection) else {
            coordinator.lock()
            return
        }
        coordinator.use(entry, field: .password, paste: true)
    }

    func secondary(at selection: Int) -> Bool {
        guard let entry = entry(at: selection) else { return false }
        coordinator.use(entry, field: .password, paste: false)
        return true
    }

    func pasteUsername(at selection: Int) -> Bool {
        guard let entry = entry(at: selection) else { return false }
        coordinator.use(entry, field: .username, paste: true)
        return true
    }

    func pasteKeepingWindowOpen(at selection: Int) -> Bool {
        guard let entry = entry(at: selection) else { return false }
        coordinator.use(entry, field: .totp, paste: true)
        return true
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let entry = entry(at: selection) else {
            return PopoverMenuContent(items: databaseActions)
        }
        var items: [PopoverMenuItem] = []
        for field in KeePassEntry.Field.allCases {
            items.append(PopoverMenuItem(title: "Paste \(field.rawValue)", systemImage: "doc.on.clipboard",
                shortcut: pasteShortcut(for: field)
            ) {
                coordinator.use(entry, field: field, paste: true)
            })
            items.append(PopoverMenuItem(title: "Copy \(field.rawValue)", systemImage: "doc.on.doc",
                shortcut: copyShortcut(for: field)
            ) {
                coordinator.use(entry, field: field, paste: false)
            })
        }
        items.append(PopoverMenuItem(title: "Open URL", systemImage: "globe", shortcut: "⌘O") { coordinator.openURL(entry) })
        items.append(PopoverMenuItem(
            title: coordinator.store.isPinned(entry) ? "Unpin Entry" : "Pin Entry", systemImage: "star", shortcut: "⌘."
        ) { coordinator.togglePin(entry) })
        items.append(contentsOf: databaseActions)
        return PopoverMenuContent(header: entry.title, items: items)
    }

    private var databaseActions: [PopoverMenuItem] {
        guard !coordinator.isLoading else { return [] }
        var items = [PopoverMenuItem(title: "Change Database…", systemImage: "folder", shortcut: "⇧⌘O") {
            coordinator.pickFile(keyFile: false)
        }]
        if !coordinator.isUnlocked, !coordinator.store.databasePath.isEmpty {
            items.append(PopoverMenuItem(title: "Choose Key File…", systemImage: "key", shortcut: "⇧⌘F") {
                coordinator.pickFile(keyFile: true)
            })
            if !coordinator.store.keyFilePath.isEmpty {
                items.append(PopoverMenuItem(title: "Remove Key File", systemImage: "xmark", shortcut: "⌥⇧⌘F") {
                    coordinator.removeKeyFile()
                })
            }
        }
        items.append(PopoverMenuItem(
            title: "Auto-lock…", icon: .symbol("timer"), shortcut: "⇧⌘L",
            detail: KeePassAutoLock.title(seconds: coordinator.store.autoLockSeconds)
        ) { coordinator.showAutoLockSettings() })
        if coordinator.isUnlocked {
            items.append(PopoverMenuItem(title: "Lock Database", systemImage: "lock", shortcut: "⌘L") { coordinator.lock() })
        }
        return items
    }

    private func pasteShortcut(for field: KeePassEntry.Field) -> String {
        switch field {
        case .password: "↵"
        case .username: "⇧↵"
        case .totp: "⌥↵"
        case .url: "⇧⌘Y"
        }
    }

    private func copyShortcut(for field: KeePassEntry.Field) -> String {
        switch field {
        case .password: "⌘↵"
        case .username: "⌘U"
        case .totp: "⇧⌘T"
        case .url: "⌘Y"
        }
    }

    func dispatchShortcut(key: KeyEquivalent, modifiers: EventModifiers, at selection: Int) -> Bool {
        guard !coordinator.isShowingAutoLockSettings, modifiers.contains(.command), key != .return else { return false }
        let flags = modifiers.intersection([.control, .option, .shift, .command])
        let chord = (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "")
            + (flags.contains(.shift) ? "⇧" : "") + "⌘" + String(key.character).uppercased()
        if chord == "⇧⌘U" { return pasteUsername(at: selection) }
        guard let action = actions(at: selection)?.items.first(where: { $0.shortcut == chord }) else { return false }
        action.action()
        return true
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(KeePassView(
            entries: rows, selection: selection, scroll: scroll,
            onActivate: { entry in coordinator.use(entry, field: .password, paste: true) },
            onActions: { entry in
                if let index = rows.firstIndex(of: entry) { vm.selection = index }
                openActions()
            }))
    }
}
