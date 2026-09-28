import Foundation

/// Parsed view of the Keychain credential blob Claude Code stores:
/// `{"claudeAiOauth": {"accessToken", "refreshToken", "expiresAt", "subscriptionType", ...}}`
public struct CredentialInfo: Equatable, Sendable {
    public var plan: String?
    public var expiresAt: Date?

    public init(blob: Data) {
        let root = (try? JSONSerialization.jsonObject(with: blob)) as? [String: Any]
        let oauth = root?["claudeAiOauth"] as? [String: Any]
        plan = oauth?["subscriptionType"] as? String
        if let millis = (oauth?["expiresAt"] as? NSNumber)?.doubleValue {
            expiresAt = Date(timeIntervalSince1970: millis / 1000)
        } else {
            expiresAt = nil
        }
    }
}
