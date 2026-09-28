import Foundation

struct ShellResult {
    var status: Int32
    var stdout: Data
    var stderr: Data

    var stdoutString: String { String(decoding: stdout, as: UTF8.self) }
    var stderrString: String { String(decoding: stderr, as: UTF8.self) }
}

enum Shell {
    /// Runs an executable synchronously, optionally feeding stdin.
    static func run(_ path: String, _ arguments: [String], stdin: Data? = nil) throws -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        let input = Pipe()
        process.standardInput = input

        try process.run()
        if let stdin {
            input.fileHandleForWriting.write(stdin)
        }
        try? input.fileHandleForWriting.close()

        // Drain both pipes concurrently so a full buffer cannot deadlock.
        let errBox = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            errBox.data = err.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()

        return ShellResult(status: process.terminationStatus, stdout: outData, stderr: errBox.data)
    }
}

private final class DataBox: @unchecked Sendable {
    var data = Data()
}
