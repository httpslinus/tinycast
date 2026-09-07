import CryptoKit
import Foundation
import Observation

@MainActor @Observable
final class KeePassStore {
    private let defaults: UserDefaults
    private(set) var databasePath: String
    private(set) var keyFilePath: String
    private(set) var autoLockSeconds: Int?
    private(set) var pins: Set<String>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let savedDelay = defaults.object(forKey: "keepassAutoLockSeconds") as? Int
        if savedDelay == 0 {
            autoLockSeconds = nil
        } else if let savedDelay, KeePassAutoLock.presets.contains(savedDelay) {
            autoLockSeconds = savedDelay
        } else { autoLockSeconds = KeePassAutoLock.defaultSeconds }
        databasePath = defaults.string(forKey: "keepassDatabasePath") ?? ""
        keyFilePath = defaults.string(forKey: "keepassKeyFilePath") ?? ""
        pins = Set(defaults.stringArray(forKey: "keepassPinnedEntries") ?? [])
    }

    func selectDatabase(_ url: URL) {
        databasePath = url.path
        keyFilePath = ""
        defaults.set(databasePath, forKey: "keepassDatabasePath")
        defaults.removeObject(forKey: "keepassKeyFilePath")
    }

    func selectKeyFile(_ url: URL?) {
        keyFilePath = url?.path ?? ""
        defaults.set(keyFilePath, forKey: "keepassKeyFilePath")
    }

    func setAutoLock(seconds: Int?) {
        if let seconds, !KeePassAutoLock.presets.contains(seconds) { return }
        autoLockSeconds = seconds
        defaults.set(seconds ?? 0, forKey: "keepassAutoLockSeconds")
    }

    func isPinned(_ entry: KeePassEntry) -> Bool { pins.contains(pinID(entry)) }

    func togglePin(_ entry: KeePassEntry) {
        let id = pinID(entry)
        if !pins.insert(id).inserted { pins.remove(id) }
        defaults.set(pins.sorted(), forKey: "keepassPinnedEntries")
    }

    private func pinID(_ entry: KeePassEntry) -> String {
        SHA256.hash(data: Data("\(databasePath.utf8.count):\(databasePath)\(entry.id)".utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
}
