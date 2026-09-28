import Foundation

/// Reads and replaces only the `oauthAccount` key of `~/.claude.json`,
/// leaving every other key untouched.
public struct ClaudeConfigFile: OAuthAccountStore {
    public static let key = "oauthAccount"

    public let url: URL

    public init(url: URL = ClaudeConfigFile.defaultURL) {
        self.url = url
    }

    /// Honors `CLAUDE_CONFIG_DIR` the same way Claude Code does.
    public static var defaultURL: URL {
        if let dir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !dir.isEmpty {
            return URL(fileURLWithPath: dir).appendingPathComponent(".claude.json")
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
    }

    private var resolvedURL: URL { url.resolvingSymlinksInPath() }

    public func readOAuthAccount() throws -> Data? {
        guard let root = try readRoot() else { return nil }
        guard let account = root[Self.key], !(account is NSNull) else { return nil }
        return try JSONSerialization.data(withJSONObject: account, options: [.sortedKeys])
    }

    public func writeOAuthAccount(_ json: Data) throws {
        guard var root = try readRoot() else {
            throw ClaudeBarError.configFileMissing(url.path)
        }
        root[Self.key] = try JSONSerialization.jsonObject(with: json)

        let target = resolvedURL
        let backup = target.appendingPathExtension("claudebar.bak")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.copyItem(at: target, to: backup)

        var data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .withoutEscapingSlashes]
        )
        data.append(contentsOf: Array("\n".utf8))
        try data.write(to: target, options: .atomic)
    }

    private func readRoot() throws -> [String: Any]? {
        let target = resolvedURL
        guard FileManager.default.fileExists(atPath: target.path) else { return nil }
        let data = try Data(contentsOf: target)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeBarError.commandFailed("\(target.path) is not a JSON object.")
        }
        return root
    }
}
