import Foundation

/// Parsed view of the Keychain credential blob Claude Code stores:
/// `{"claudeAiOauth": {"accessToken", "refreshToken", "expiresAt", "subscriptionType", ...}}`
public struct CredentialInfo: Equatable, Sendable {
    public var plan: String?
    public var expiresAt: Date?
    public var accessToken: String?

    /// True when the access token is missing or expires within `margin`.
    public func isExpired(now: Date = Date(), margin: TimeInterval = 60) -> Bool {
        guard accessToken?.isEmpty == false else { return true }
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSince(now) < margin
    }

    public init(blob: Data) {
        let root = (try? JSONSerialization.jsonObject(with: blob)) as? [String: Any]
        let oauth = root?["claudeAiOauth"] as? [String: Any]
        plan = oauth?["subscriptionType"] as? String
        accessToken = oauth?["accessToken"] as? String
        if let millis = (oauth?["expiresAt"] as? NSNumber)?.doubleValue {
            expiresAt = Date(timeIntervalSince1970: millis / 1000)
        } else {
            expiresAt = nil
        }
    }
}
