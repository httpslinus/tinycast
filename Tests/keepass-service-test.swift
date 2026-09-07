import Foundation

@main
struct KeePassServiceTests {
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("keepass-tests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fakeCLI = directory.appendingPathComponent("fake-cli")
        try """
        #!/bin/sh
        read -r password
        [ "$password" = "fixture secret" ] || exit 1
        printf '"Group","Title","Username","Password","URL","Notes","TOTP"\\n'
        printf '"Root","Fixture","alice","secret","https://example.com","",""\\n'
        """.write(to: fakeCLI, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fakeCLI.path)
        let database = directory.appendingPathComponent("fixture ; $(touch injected).kdbx")
        let entries = try await KeePassService.load(
            executable: fakeCLI, database: database, password: "fixture secret", keyFile: nil)
        precondition(entries.count == 1 && entries[0].username == "alice")
        do {
            _ = try await KeePassService.load(executable: fakeCLI, database: database, password: "bad", keyFile: nil)
            preconditionFailure("Wrong password accepted")
        } catch KeePassService.Failure.unlock {}
        do {
            _ = try await KeePassService.load(executable: fakeCLI, database: database, password: "bad\npassword", keyFile: nil)
            preconditionFailure("Multiline password accepted")
        } catch KeePassService.Failure.invalidPassword {}
        let slowCLI = directory.appendingPathComponent("slow-cli")
        try "#!/bin/sh\nexec /bin/sleep 20\n".write(to: slowCLI, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: slowCLI.path)
        let pending = Task.detached {
            try await KeePassService.load(executable: slowCLI, database: database, password: "", keyFile: nil)
        }
        try await Task.sleep(for: .milliseconds(100))
        pending.cancel()
        do {
            _ = try await pending.value
            preconditionFailure("Cancelled operation published entries")
        } catch is CancellationError {}
        print("KeePass process: stdin credentials, failures, and cancellation passed")

        let executable = URL(fileURLWithPath: "/Applications/KeePassXC.app/Contents/MacOS/keepassxc-cli")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            print("SKIP real KDBX fixtures: KeePassXC is not installed")
            return
        }
        try run(executable, ["db-create", "-q", "-p", "-t", "100", database.path], input: "fixture\nfixture\n")
        try run(executable, ["add", "-q", "-u", "alice", "--url", "https://example.com", "-p", database.path, "Fixture"],
                input: "fixture\nentry password\n")
        let loaded = try await KeePassService.load(executable: executable, database: database, password: "fixture", keyFile: nil)
        precondition(loaded.count == 1 && loaded[0].password == "entry password" && loaded[0].username == "alice")
        do {
            _ = try await KeePassService.load(executable: executable, database: database, password: "wrong", keyFile: nil)
            preconditionFailure("Real KDBX accepted wrong password")
        } catch KeePassService.Failure.unlock {}
        let keyFile = directory.appendingPathComponent("fixture.keyx")
        let keyDatabase = directory.appendingPathComponent("key-only.kdbx")
        try run(executable, ["db-create", "-q", "--set-key-file", keyFile.path, "-t", "100", keyDatabase.path])
        let empty = try await KeePassService.load(executable: executable, database: keyDatabase, password: "", keyFile: keyFile)
        precondition(empty.isEmpty)
        let combined = directory.appendingPathComponent("combined.kdbx")
        try run(executable, ["db-create", "-q", "-p", "--set-key-file", keyFile.path, "-t", "100", combined.path],
                input: "fixture\nfixture\n")
        let combinedEntries = try await KeePassService.load(
            executable: executable, database: combined, password: "fixture", keyFile: keyFile)
        precondition(combinedEntries.isEmpty)
        print("Real KDBX: password unlock, wrong password, key-file-only, and combined credentials passed")
    }

    private static func run(_ executable: URL, _ arguments: [String], input: String = "") throws {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = pipe
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        try pipe.fileHandleForWriting.write(contentsOf: Data(input.utf8))
        try pipe.fileHandleForWriting.close()
        process.waitUntilExit()
        precondition(process.terminationStatus == 0, "Fixture setup failed")
    }
}
