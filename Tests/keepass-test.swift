import Foundation

@main
struct KeePassTests {
    @MainActor
    static func main() async throws {
        let header = "\"Group\",\"Title\",\"Username\",\"Password\",\"URL\",\"Notes\",\"TOTP\"\r\n"
        let csv = header + "\"Root/Work\",\"Example, Inc\",\"alice\",\" secret \"\"quoted\"\" \","
            + "\"https://example.com\",\"line one\r\nline two\",\"\"\r\n"
            + "\"Root/Recycle Bin\",\"Deleted\",\"\",\"hidden\",\"\",\"\",\"\"\n"
            + "\"Root\",\"Root Entry\",\"bob\",\"{USERNAME}\",\"\",\"\",\"\""
        let entries = try KeePassCSV.entries(from: Data(csv.utf8))
        precondition(entries.count == 2)
        precondition(entries[0].title == "Example, Inc" && entries[0].group == "Work")
        precondition(entries[0].password == " secret \"quoted\" ")
        precondition(entries[0].notes == "line one\r\nline two")
        precondition(entries[1].group == "")
        let expanded = try entries[1].value(.password, at: Date(timeIntervalSince1970: 0))
        precondition(expanded == "bob")
        precondition(entries[0].matches("ALICE example", folder: "Work"))
        precondition(!entries[0].matches("secret", folder: ""))
        precondition(!entries[0].matches("", folder: "Wor"))
        for invalid in ["not csv", header + "\"unterminated", header + "one,two,three", header + "\"a\"x,b"] {
            do {
                _ = try KeePassCSV.entries(from: Data(invalid.utf8))
                preconditionFailure("Malformed CSV accepted")
            } catch KeePassCSV.Failure.invalid {}
        }
        let duplicate = header + "Root,A,b,c,d,e,f\nRoot,A,b,x,y,z,f\n"
        let duplicates = try KeePassCSV.entries(from: Data(duplicate.utf8))
        precondition(Set(duplicates.map(\.id)).count == 2)
        let empty = try KeePassCSV.entries(from: Data(header.utf8))
        precondition(empty.isEmpty)

        let secrets = [
            "SHA1": "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ",
            "SHA256": "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZA====",
            "SHA512": "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
                + "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNA="
        ]
        let vectors: [(TimeInterval, [String])] = [
            (59, ["94287082", "46119246", "90693936"]),
            (1_111_111_109, ["07081804", "68084774", "25091201"]),
            (1_111_111_111, ["14050471", "67062674", "99943326"]),
            (1_234_567_890, ["89005924", "91819424", "93441116"]),
            (2_000_000_000, ["69279037", "90698825", "38618901"]),
            (20_000_000_000, ["65353130", "77737706", "47863826"])
        ]
        for (time, codes) in vectors {
            for (index, algorithm) in ["SHA1", "SHA256", "SHA512"].enumerated() {
                let uri = "otpauth://totp/Test?secret=\(secrets[algorithm] ?? "")&algorithm=\(algorithm)&digits=8"
                let code = try KeePassTOTP.generate(uri, at: Date(timeIntervalSince1970: time))
                precondition(code == codes[index], "RFC 6238 vector failed for \(algorithm)")
            }
        }
        for suffix in ["&period=0", "&digits=99", "&algorithm=MD5", "&secret=BAD", "&period=garbage"] {
            do {
                _ = try KeePassTOTP.generate(
                    "otpauth://totp/Test?secret=GEZDGNBVGY3TQOJQ" + suffix, at: Date())
                preconditionFailure("Invalid TOTP accepted")
            } catch KeePassTOTP.Failure.invalid {}
        }
        let ownPID: Int32 = 10
        precondition(KeePassPasteTarget.index(
            processIDs: [20, 30, 40], ownProcessID: ownPID, terminated: []) == 0)
        precondition(KeePassPasteTarget.index(
            processIDs: [ownPID, nil, 40], ownProcessID: ownPID, terminated: []) == 2)
        precondition(KeePassPasteTarget.index(
            processIDs: [nil, ownPID, 40], ownProcessID: ownPID, terminated: []) == 2)
        precondition(KeePassPasteTarget.index(
            processIDs: [20, 30, 40], ownProcessID: ownPID, terminated: [20]) == 1)
        precondition(KeePassPasteTarget.index(
            processIDs: [ownPID, nil, 40], ownProcessID: ownPID, terminated: [40]) == nil)

        let suite = "com.tinycast.keepass-test.\(UUID())"
        guard let defaults = UserDefaults(suiteName: suite) else { preconditionFailure("No defaults") }
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = KeePassStore(defaults: defaults)
        precondition(store.autoLockSeconds == 300)
        for seconds in KeePassAutoLock.presets {
            store.setAutoLock(seconds: seconds)
            precondition(KeePassStore(defaults: defaults).autoLockSeconds == seconds)
        }
        store.setAutoLock(seconds: nil)
        precondition(KeePassStore(defaults: defaults).autoLockSeconds == nil)
        for invalid in [0, -1, 47, Int.max] {
            store.setAutoLock(seconds: invalid)
            precondition(store.autoLockSeconds == nil)
            defaults.set(invalid == 0 ? -2 : invalid, forKey: "keepassAutoLockSeconds")
            precondition(KeePassStore(defaults: defaults).autoLockSeconds == 300)
        }
        precondition(KeePassAutoLock.title(seconds: nil) == "Never")
        precondition(KeePassAutoLock.title(seconds: 60) == "1 minute")
        precondition(KeePassAutoLock.title(seconds: 3600) == "1 hour")
        store.selectDatabase(URL(fileURLWithPath: "/tmp/fixture.kdbx"))
        store.togglePin(entries[0])
        precondition(store.isPinned(entries[0]))
        precondition(KeePassStore(defaults: defaults).isPinned(entries[0]))
        precondition(!(defaults.stringArray(forKey: "keepassPinnedEntries") ?? []).joined().contains("alice"))
        store.selectKeyFile(URL(fileURLWithPath: "/tmp/fixture.key"))
        store.selectDatabase(URL(fileURLWithPath: "/tmp/another.kdbx"))
        precondition(store.keyFilePath.isEmpty && !store.isPinned(entries[0]))
        print("KeePass: CSV, filtering, placeholders, RFC 6238 vectors, and isolated preferences passed")
    }
}
