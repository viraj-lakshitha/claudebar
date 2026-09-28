import Foundation

/// The login Claude Code is currently using.
public struct LiveLogin: Equatable {
    public var credentialBlob: Data
    public var oauthAccount: Data
    public var account: OAuthAccountInfo
    public var credential: CredentialInfo
}

/// Captures, stores and swaps Claude Code logins.
public final class AccountSwitcher {
    public let maxProfiles: Int
    public private(set) var profiles: [Profile]

    private let live: LiveCredentialStore
    private let config: OAuthAccountStore
    private let vault: ProfileVault
    private let store: ProfileStore

    public init(
        live: LiveCredentialStore,
        config: OAuthAccountStore,
        vault: ProfileVault,
        store: ProfileStore,
        maxProfiles: Int = 2
    ) throws {
        self.live = live
        self.config = config
        self.vault = vault
        self.store = store
        self.maxProfiles = maxProfiles
        self.profiles = try store.load()
    }

    // MARK: - Reading state

    /// The login Claude Code is using right now, or nil if logged out.
    public func currentLogin() throws -> LiveLogin? {
        guard let blob = try live.read(), let accountJSON = try config.readOAuthAccount() else {
            return nil
        }
        return LiveLogin(
            credentialBlob: blob,
            oauthAccount: accountJSON,
            account: try OAuthAccountInfo(json: accountJSON),
            credential: CredentialInfo(blob: blob)
        )
    }

    public func profile(matching login: LiveLogin) -> Profile? {
        profiles.first { $0.accountUuid == login.account.accountUuid }
    }

    // MARK: - Mutations

    /// Saves the current login as a profile, or refreshes the matching one.
    @discardableResult
    public func captureCurrent(label: String? = nil) throws -> Profile {
        guard let login = try currentLogin() else { throw ClaudeBarError.noLiveCredential }
        if let existing = profile(matching: login) {
            return try refresh(existing, from: login, label: label)
        }
        guard profiles.count < maxProfiles else { throw ClaudeBarError.profileLimitReached(maxProfiles) }

        let profile = Profile(
            label: label,
            email: login.account.email,
            displayName: login.account.displayName,
            organizationName: login.account.organizationName,
            plan: login.credential.plan,
            accountUuid: login.account.accountUuid
        )
        try vault.save(ProfileSecret(credentialBlob: login.credentialBlob, oauthAccount: login.oauthAccount), for: profile.id)
        profiles.append(profile)
        try store.save(profiles)
        return profile
    }

    /// Copies the live tokens into the active profile's vault entry if they
    /// changed. Claude Code rotates refresh tokens, so a saved snapshot goes
    /// stale unless it is kept in sync.
    /// Returns the active profile, if the current login is a saved one.
    @discardableResult
    public func syncActive() throws -> Profile? {
        guard let login = try currentLogin(), let active = profile(matching: login) else { return nil }
        let stored = try vault.load(active.id)
        if stored?.credentialBlob == login.credentialBlob, stored?.oauthAccount == login.oauthAccount {
            return active
        }
        return try refresh(active, from: login, label: nil)
    }

    /// Makes `id` the account Claude Code uses.
    ///
    /// - Parameter discardUnsaved: allow switching even when the current login
    ///   is not saved in ClaudeBar (it will be lost).
    public func switchTo(_ id: UUID, discardUnsaved: Bool = false) throws {
        guard let target = profiles.first(where: { $0.id == id }) else { throw ClaudeBarError.profileNotFound }
        guard let secret = try vault.load(id) else { throw ClaudeBarError.missingSecret }

        let current = try currentLogin()
        if let current {
            if current.account.accountUuid == target.accountUuid {
                try syncActive()
                return
            }
            if let active = profile(matching: current) {
                // Save the newest tokens of the account we're leaving.
                try refresh(active, from: current, label: nil)
            } else if !discardUnsaved {
                throw ClaudeBarError.unsavedCurrentLogin(email: current.account.email)
            }
        }

        let previousBlob = try live.read()
        try live.write(secret.credentialBlob)
        do {
            try config.writeOAuthAccount(secret.oauthAccount)
        } catch {
            if let previousBlob { try? live.write(previousBlob) }
            throw error
        }
    }

    public func rename(_ id: UUID, to label: String?) throws {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { throw ClaudeBarError.profileNotFound }
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        profiles[index].label = (trimmed?.isEmpty ?? true) ? nil : trimmed
        try store.save(profiles)
    }

    /// Forgets a saved profile. Does not log Claude Code out.
    public func remove(_ id: UUID) throws {
        try vault.delete(id)
        profiles.removeAll { $0.id == id }
        try store.save(profiles)
    }

    // MARK: - Private

    @discardableResult
    private func refresh(_ profile: Profile, from login: LiveLogin, label: String?) throws -> Profile {
        try vault.save(ProfileSecret(credentialBlob: login.credentialBlob, oauthAccount: login.oauthAccount), for: profile.id)
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return profile }
        profiles[index].email = login.account.email
        profiles[index].displayName = login.account.displayName
        profiles[index].organizationName = login.account.organizationName
        profiles[index].plan = login.credential.plan ?? profiles[index].plan
        profiles[index].capturedAt = Date()
        if let label, !label.isEmpty { profiles[index].label = label }
        try store.save(profiles)
        return profiles[index]
    }
}
