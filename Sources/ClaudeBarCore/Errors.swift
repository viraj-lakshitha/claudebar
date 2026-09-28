import Foundation

public enum ClaudeBarError: LocalizedError, Equatable {
    case noLiveCredential
    case noOAuthAccount
    case malformedOAuthAccount
    case configFileMissing(String)
    case profileNotFound
    case missingSecret
    case profileLimitReached(Int)
    case unsavedCurrentLogin(email: String)
    case keychain(String)
    case commandFailed(String)
    case usageUnauthorized

    public var errorDescription: String? {
        switch self {
        case .noLiveCredential:
            return "No Claude Code login found in the Keychain. Run `claude` and log in first."
        case .noOAuthAccount:
            return "~/.claude.json has no oauthAccount. Run `claude` and log in first."
        case .malformedOAuthAccount:
            return "The oauthAccount entry in ~/.claude.json could not be read."
        case .configFileMissing(let path):
            return "Claude Code config not found at \(path)."
        case .profileNotFound:
            return "That account is no longer saved."
        case .missingSecret:
            return "The saved credentials for this account are missing. Log in to it again and re-save it."
        case .profileLimitReached(let max):
            return "ClaudeBar holds \(max) accounts. Remove one in Settings first."
        case .unsavedCurrentLogin(let email):
            return "The current login (\(email)) is not saved in ClaudeBar and would be lost."
        case .keychain(let message):
            return "Keychain error: \(message)"
        case .commandFailed(let message):
            return message
        case .usageUnauthorized:
            return "Sign-in expired. Switch to this account and run `claude` to refresh it."

        }
    }
}
