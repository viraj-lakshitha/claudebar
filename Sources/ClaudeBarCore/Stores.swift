import Foundation

/// The Keychain item Claude Code itself reads (`Claude Code-credentials`).
public protocol LiveCredentialStore {
    func read() throws -> Data?
    func write(_ blob: Data) throws
}

/// The `oauthAccount` object inside `~/.claude.json`.
public protocol OAuthAccountStore {
    func readOAuthAccount() throws -> Data?
    func writeOAuthAccount(_ json: Data) throws
}

/// ClaudeBar's own secure storage for each saved account.
public protocol ProfileVault {
    func load(_ id: UUID) throws -> ProfileSecret?
    func save(_ secret: ProfileSecret, for id: UUID) throws
    func delete(_ id: UUID) throws
}

/// Non-secret profile metadata.
public protocol ProfileStore {
    func load() throws -> [Profile]
    func save(_ profiles: [Profile]) throws
}
