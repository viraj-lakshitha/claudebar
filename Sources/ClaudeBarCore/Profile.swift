import Foundation

/// Non-secret metadata about a saved Claude Code account.
/// The secrets themselves live in `ProfileVault`.
public struct Profile: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var label: String?
    public var email: String
    public var displayName: String?
    public var organizationName: String?
    public var plan: String?
    public var accountUuid: String
    public var capturedAt: Date

    public init(
        id: UUID = UUID(),
        label: String? = nil,
        email: String,
        displayName: String? = nil,
        organizationName: String? = nil,
        plan: String? = nil,
        accountUuid: String,
        capturedAt: Date = Date()
    ) {
        self.id = id
        self.label = label
        self.email = email
        self.displayName = displayName
        self.organizationName = organizationName
        self.plan = plan
        self.accountUuid = accountUuid
        self.capturedAt = capturedAt
    }

    /// Name shown in the menu: the custom label if set, otherwise the email.
    public var title: String {
        if let label, !label.trimmingCharacters(in: .whitespaces).isEmpty { return label }
        return email
    }

    /// One or two characters for the menu bar.
    public var shortTitle: String {
        String(title.prefix(1)).uppercased()
    }

    /// Human readable plan badge, e.g. "Max", "Pro".
    public var planBadge: String? {
        guard let plan, !plan.isEmpty else { return nil }
        return plan.prefix(1).uppercased() + plan.dropFirst()
    }
}

/// Secrets captured for a profile: the raw Keychain credential blob and the
/// raw `oauthAccount` JSON object from `~/.claude.json`.
public struct ProfileSecret: Codable, Equatable, Sendable {
    public var credentialBlob: Data
    public var oauthAccount: Data

    public init(credentialBlob: Data, oauthAccount: Data) {
        self.credentialBlob = credentialBlob
        self.oauthAccount = oauthAccount
    }
}
