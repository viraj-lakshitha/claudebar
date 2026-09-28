import Foundation

/// Access to Claude Code's own Keychain item via `/usr/bin/security`.
///
/// Claude Code creates and updates this item through the `security` tool, so
/// the item's access list already trusts that binary. Going through it keeps
/// macOS from prompting for Keychain access on every switch.
public struct ClaudeKeychain: LiveCredentialStore {
    public static let defaultService = "Claude Code-credentials"
    static let securityPath = "/usr/bin/security"
    static let itemNotFound: Int32 = 44

    public let service: String

    public init(service: String = ClaudeKeychain.defaultService) {
        self.service = service
    }

    public func read() throws -> Data? {
        let result = try Shell.run(Self.securityPath, ["find-generic-password", "-s", service, "-w"])
        if result.status == Self.itemNotFound { return nil }
        guard result.status == 0 else {
            throw ClaudeBarError.keychain(result.stderrString.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let value = result.stdoutString.trimmingCharacters(in: .newlines)
        return value.isEmpty ? nil : Data(value.utf8)
    }

    public func write(_ blob: Data) throws {
        let account = try existingAccountName() ?? NSUserName()
        // `security -i` reads the command from stdin, so the secret never shows
        // up in the process list. `-X` takes the password as hex.
        let hex = blob.map { String(format: "%02x", $0) }.joined()
        let command = "add-generic-password -U -s \(Self.quote(service)) -a \(Self.quote(account)) -X \(hex)\n"
        let result = try Shell.run(Self.securityPath, ["-i"], stdin: Data(command.utf8))
        guard result.status == 0, !result.stderrString.localizedCaseInsensitiveContains("error") else {
            throw ClaudeBarError.keychain(result.stderrString.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// The `acct` attribute of the existing item, so updates hit the same item.
    func existingAccountName() throws -> String? {
        let result = try Shell.run(Self.securityPath, ["find-generic-password", "-s", service])
        guard result.status == 0 else { return nil }
        // `security` prints attributes on stdout or stderr depending on version.
        return Self.parseAccount(result.stdoutString + "\n" + result.stderrString)
    }

    /// Parses a line like `    "acct"<blob>="viraj"`.
    static func parseAccount(_ output: String) -> String? {
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\"acct\"<blob>=\""), trimmed.hasSuffix("\"") else { continue }
            let value = trimmed.dropFirst("\"acct\"<blob>=\"".count).dropLast()
            return String(value)
        }
        return nil
    }

    static func quote(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
