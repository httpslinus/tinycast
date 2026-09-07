import AppKit

@MainActor
final class KeePassClipboard {
    private let pasteboard: NSPasteboard
    private var clearTask: Task<Void, Never>?
    private var pasteTask: Task<Void, Never>?
    private var changeCount: Int?

    init(pasteboard: NSPasteboard = .general) { self.pasteboard = pasteboard }

    func write(_ text: String, pastingInto app: NSRunningApplication? = nil) {
        clearTask?.cancel()
        pasteTask?.cancel()
        let markers: [NSPasteboard.PasteboardType] = [
            .init("org.nspasteboard.ConcealedType"), .init("org.nspasteboard.TransientType"),
            .init("com.apple.is-sensitive"), .init("com.tinycast.internal")
        ]
        pasteboard.clearContents()
        pasteboard.declareTypes([.string] + markers, owner: nil)
        pasteboard.setString(text, forType: .string)
        for marker in markers { pasteboard.setData(Data(), forType: marker) }
        changeCount = pasteboard.changeCount
        clearTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            self?.clear()
        }
        if let app {
            app.activate()
            pasteTask = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                guard let self, pasteboard.changeCount == changeCount else { return }
                Paster.postCommandV(toPid: app.processIdentifier)
            }
        }
    }

    func clear() {
        clearTask?.cancel()
        clearTask = nil
        pasteTask?.cancel()
        pasteTask = nil
        if changeCount == pasteboard.changeCount { pasteboard.clearContents() }
        changeCount = nil
    }

    isolated deinit {
        clearTask?.cancel()
        pasteTask?.cancel()
    }
}
