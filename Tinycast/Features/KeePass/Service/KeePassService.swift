import Foundation

nonisolated enum KeePassService {
    enum Failure: LocalizedError {
        case unavailable, unlock, oversized, invalidPassword
        var errorDescription: String? {
            switch self {
            case .unavailable: return "Install KeePassXC in Applications to open KeePass databases."
            case .unlock: return "Couldn’t unlock the database. Check the file, password, and key file, then try again."
            case .oversized: return "This database is too large to search in Tinycast (32 MB export limit)."
            case .invalidPassword: return "The database password cannot contain a line break and must be under 4 KB."
            }
        }
    }

    static func load(executable: URL, database: URL, password: String, keyFile: URL?) async throws -> [KeePassEntry] {
        guard !password.contains(where: \.isNewline), password.utf8.count < 4096 else {
            throw Failure.invalidPassword
        }
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw Failure.unavailable }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["export", "-q", "-f", "csv"]
            + (keyFile.map { ["-k", $0.path] } ?? [])
            + (password.isEmpty ? ["--no-password"] : []) + [database.path]
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try process.run()
            let timeout = Task {
                try await Task.sleep(for: .seconds(30))
                if process.isRunning { process.terminate() }
            }
            defer {
                timeout.cancel()
                try? input.fileHandleForWriting.close()
                try? output.fileHandleForReading.close()
                if process.isRunning { process.terminate() }
                process.waitUntilExit()
            }
            try Task.checkCancellation()
            if !password.isEmpty {
                _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
                try input.fileHandleForWriting.write(contentsOf: Data((password + "\n").utf8))
            }
            try input.fileHandleForWriting.close()
            var data = Data()
            while let chunk = try output.fileHandleForReading.read(upToCount: 65_536), !chunk.isEmpty {
                try Task.checkCancellation()
                guard data.count + chunk.count <= 32 * 1024 * 1024 else { throw Failure.oversized }
                data.append(chunk)
            }
            process.waitUntilExit()
            try Task.checkCancellation()
            guard process.terminationStatus == 0 else { throw Failure.unlock }
            return try KeePassCSV.entries(from: data)
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }
}
