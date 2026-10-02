import AppKit
import Observation
import UniformTypeIdentifiers

@MainActor @Observable
final class KeePassCoordinator {
    let store: KeePassStore
    private(set) var entries: [KeePassEntry] = []
    private(set) var isUnlocked = false
    private(set) var isLoading = false
    private(set) var failure: String?
    private(set) var isShowingAutoLockSettings = false
    var isShowingForm: Bool { !isUnlocked || isShowingAutoLockSettings }
    var password = ""
    var folder = ""
    private(set) var formFocusStep = 0
    private unowned let core: AppCore
    private let clipboard: KeePassClipboard
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var lockTask: Task<Void, Never>?
    @ObservationIgnored private var pickerTask: Task<Void, Never>?
    @ObservationIgnored private var tokens: [NotificationToken] = []
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var lastExternalApp: NSRunningApplication?

    init(store: KeePassStore, clipboard: KeePassClipboard, core: AppCore) {
        self.store = store
        self.clipboard = clipboard
        self.core = core
    }

    func start() {
        rememberExternalApp(NSWorkspace.shared.frontmostApplication)
        let center = NSWorkspace.shared.notificationCenter
        tokens.append(NotificationToken(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor [weak self] in self?.rememberExternalApp(app) }
        }, center: center))
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            tokens.append(NotificationToken(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.lock() }
            }, center: center))
        }
        let distributed = DistributedNotificationCenter.default()
        tokens.append(NotificationToken(distributed.addObserver(
            forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.lock() }
        }, center: distributed))
    }

    func show() {
        rememberExternalApp(core.paletteCoordinator.targetApp)
        if core.paletteCoordinator.isVisible {
            core.palette.prepare(mode: .keepass)
        } else { core.paletteCoordinator.showPalette(mode: .keepass) }
        touch()
    }

    func advanceFormFocus(backwards: Bool) {
        formFocusStep += backwards ? -1 : 1
    }

    var folders: [String] { Array(Set(entries.map(\.group).filter { !$0.isEmpty })).sorted() }

    func results(query: String) -> [KeePassEntry] {
        let matches = entries.filter { $0.matches(query, folder: folder) }
        return matches.filter { store.isPinned($0) } + matches.filter { !store.isPinned($0) }
    }

    func unlock() {
        guard !isLoading, !store.databasePath.isEmpty else { return }
        failure = nil
        isLoading = true
        let generation = UUID()
        self.generation = generation
        let secret = password
        password = ""
        let database = URL(fileURLWithPath: store.databasePath)
        let keyFile = store.keyFilePath.isEmpty ? nil : URL(fileURLWithPath: store.keyFilePath)
        let executable = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "org.keepassxc.keepassxc")?
            .appendingPathComponent("Contents/MacOS/keepassxc-cli")
            ?? URL(fileURLWithPath: "/Applications/KeePassXC.app/Contents/MacOS/keepassxc-cli")
        loadTask = Task { [weak self] in
            let worker = Task.detached {
                try await KeePassService.load(executable: executable, database: database, password: secret, keyFile: keyFile)
            }
            do {
                let entries = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: { worker.cancel() }
                guard let self, self.generation == generation, !Task.isCancelled else { return }
                self.entries = entries
                isUnlocked = true
                isLoading = false
                loadTask = nil
                core.palette.query = ""
                core.palette.selection = 0
                core.palette.focusToken = UUID()
                touch()
            } catch {
                guard let self, self.generation == generation, !Task.isCancelled else { return }
                isLoading = false
                loadTask = nil
                failure = (error as? LocalizedError)?.errorDescription ?? "Couldn’t open the database."
            }
        }
    }

    func touch() {
        guard isUnlocked else { return }
        lockTask?.cancel()
        lockTask = nil
        guard let seconds = store.autoLockSeconds else { return }
        lockTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            self?.lock()
        }
    }

    func setAutoLock(seconds: Int?) {
        store.setAutoLock(seconds: seconds)
        touch()
    }

    func showAutoLockSettings() {
        isShowingAutoLockSettings = true
        core.palette.query = ""
        touch()
    }

    func closeAutoLockSettings() {
        isShowingAutoLockSettings = false
        core.palette.focusToken = UUID()
        touch()
    }

    func selectFolder(_ value: String) {
        folder = value
        core.palette.selection = 0
        core.palette.resetToken = UUID()
        touch()
    }

    func lock() {
        generation = UUID()
        loadTask?.cancel()
        loadTask = nil
        lockTask?.cancel()
        lockTask = nil
        isShowingAutoLockSettings = false
        entries = []
        isUnlocked = false
        isLoading = false
        password = ""
        folder = ""
        failure = nil
        clipboard.clear()
        if core.palette.mode == .keepass {
            core.palette.query = ""
            core.palette.selection = 0
            core.palette.focusToken = UUID()
        }
    }

    func paletteDidHide() {
        isShowingAutoLockSettings = false
        password = ""
        if isLoading { lock() }
    }

    func pickFile(keyFile: Bool, returnToPalette: Bool = true) {
        guard pickerTask == nil else { return }
        rememberExternalApp(core.paletteCoordinator.targetApp)
        password = ""
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = keyFile ? "Choose the database’s key file." : "Choose a KeePass database."
        if !keyFile, let type = UTType(filenameExtension: "kdbx") { panel.allowedContentTypes = [type] }
        if returnToPalette { core.paletteCoordinator.hidePalette(restoreFocus: false) }
        NSApp.activate()
        pickerTask = Task { [weak self] in
            let response = await panel.begin()
            guard let self, !Task.isCancelled else { return }
            pickerTask = nil
            if response == .OK, let url = panel.url {
                lock()
                if keyFile { store.selectKeyFile(url) } else { store.selectDatabase(url) }
            }
            if returnToPalette { core.paletteCoordinator.showPalette(mode: .keepass)
            } else { core.settingsCoordinator.showSettings(tab: .keepass) }
        }
    }

    func removeKeyFile() { lock(); store.selectKeyFile(nil) }
    func togglePin(_ entry: KeePassEntry) { store.togglePin(entry); touch() }

    func use(_ entry: KeePassEntry, field: KeePassEntry.Field, paste: Bool) {
        guard isUnlocked, entries.contains(entry) else { return }
        do {
            let value = try entry.value(field, at: Date())
            guard !value.isEmpty else {
                core.showMessage("No \(field.rawValue.lowercased()) set", tone: .danger)
                return
            }
            if paste {
                guard let target = pasteTarget else {
                    core.showMessage("Choose an app to paste into, or use Copy", tone: .danger)
                    return
                }
                guard Permissions.ensureAccessibility() else {
                    core.showMessage("Allow Tinycast in System Settings › Privacy & Security › Accessibility", tone: .danger)
                    return
                }
                core.paletteCoordinator.hidePalette(restoreFocus: false)
                clipboard.write(value, pastingInto: target)
            } else {
                clipboard.write(value)
                core.showMessage("Copied \(field.rawValue.lowercased()) · clears in 30 seconds")
            }
            touch()
        } catch {
            core.showMessage(error.localizedDescription, tone: .danger)
        }
    }

    func openURL(_ entry: KeePassEntry) {
        guard isUnlocked, entries.contains(entry), let value = try? entry.value(.url, at: Date()),
            let url = URL(string: value), ["https", "http"].contains(url.scheme?.lowercased() ?? "")
        else {
            core.showMessage("This entry has no HTTP or HTTPS URL", tone: .danger)
            return
        }
        touch()
        core.paletteCoordinator.hidePalette(restoreFocus: false)
        if !NSWorkspace.shared.open(url) { core.showMessage("Couldn’t open the URL", tone: .danger) }
    }

    private func rememberExternalApp(_ app: NSRunningApplication?) {
        guard let app, !app.isTerminated,
            app.processIdentifier != NSRunningApplication.current.processIdentifier else { return }
        lastExternalApp = app
    }

    private var pasteTarget: NSRunningApplication? {
        let apps = [NSWorkspace.shared.frontmostApplication, core.paletteCoordinator.targetApp, lastExternalApp]
        let terminated = Set(apps.compactMap { app in
            app?.isTerminated == true ? app?.processIdentifier : nil
        })
        guard let index = KeePassPasteTarget.index(
            processIDs: apps.map { $0?.processIdentifier },
            ownProcessID: NSRunningApplication.current.processIdentifier, terminated: terminated)
        else { return nil }
        return apps[index]
    }

    func stop() {
        lock()
        pickerTask?.cancel()
        pickerTask = nil
        tokens = []
        lastExternalApp = nil
    }
}
