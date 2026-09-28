import Foundation

/// Parsed view of the `oauthAccount` object in `~/.claude.json`.
public struct OAuthAccountInfo: Equatable, Sendable {
    public var accountUuid: String
    public var email: String
    public var displayName: String?
    public var organizationName: String?

    public init(json: Data) throws {
        guard let object = try JSONSerialization.jsonObject(with: json) as? [String: Any] else {
            throw ClaudeBarError.malformedOAuthAccount
        }
        guard let uuid = object["accountUuid"] as? String, !uuid.isEmpty else {
            throw ClaudeBarError.malformedOAuthAccount
        }
        accountUuid = uuid
        email = object["emailAddress"] as? String ?? "unknown"
        displayName = object["displayName"] as? String
        organizationName = object["organizationName"] as? String
    }
}
