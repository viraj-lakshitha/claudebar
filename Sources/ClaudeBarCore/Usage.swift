import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One rate-limit window, e.g. the 5-hour session or the weekly limit.
public struct UsageWindow: Codable, Equatable, Sendable, Identifiable {
    public var key: String
    /// 0–100.
    public var utilization: Double
    public var resetsAt: Date?

    public var id: String { key }

    public init(key: String, utilization: Double, resetsAt: Date?) {
        self.key = key
        self.utilization = utilization
        self.resetsAt = resetsAt
    }

    public var title: String {
        switch key {
        case "five_hour": return "Session (5h)"
        case "seven_day": return "Weekly"
        case "seven_day_opus": return "Weekly · Opus"
        case "seven_day_sonnet": return "Weekly · Sonnet"
        default:
            return key.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
        }
    }

    /// Sort order: session first, then weekly, then model-specific windows.
    var rank: Int {
        switch key {
        case "five_hour": return 0
        case "seven_day": return 1
        case "seven_day_opus": return 2
        case "seven_day_sonnet": return 3
        default: return 10
        }
    }
}

/// Usage limits for one account at a point in time.
public struct UsageSnapshot: Codable, Equatable, Sendable {
    public var windows: [UsageWindow]
    public var fetchedAt: Date

    public init(windows: [UsageWindow], fetchedAt: Date = Date()) {
        self.windows = windows
        self.fetchedAt = fetchedAt
    }

    /// The 5-hour session window, which is what usually runs out first.
    public var session: UsageWindow? { windows.first { $0.key == "five_hour" } }

    /// Parses the response of `GET /api/oauth/usage`, e.g.
    /// `{"five_hour":{"utilization":23.0,"resets_at":"2026-09-28T19:59:59.9+00:00"},"seven_day":{…},"seven_day_opus":null}`.
    /// Unknown windows are kept; null or malformed entries are skipped.
    public static func parse(_ data: Data, fetchedAt: Date = Date()) throws -> UsageSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeBarError.commandFailed("Unexpected usage response.")
        }
        let windows = root.compactMap { key, value -> UsageWindow? in
            guard let object = value as? [String: Any],
                  let utilization = (object["utilization"] as? NSNumber)?.doubleValue else { return nil }
            return UsageWindow(key: key, utilization: utilization, resetsAt: parseDate(object["resets_at"] as? String))
        }
        .sorted { ($0.rank, $0.key) < ($1.rank, $1.key) }
        return UsageSnapshot(windows: windows, fetchedAt: fetchedAt)
    }

    /// ISO 8601 with optional fractional seconds of any precision.
    static func parseDate(_ string: String?) -> Date? {
        guard var string, !string.isEmpty else { return nil }
        if let dot = string.firstIndex(of: "."),
           let zone = string[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
            string.removeSubrange(dot..<zone)
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

/// Fetches plan usage limits the same way Claude Code's `/usage` does.
public struct UsageClient: Sendable {
    public static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    public init() {}

    public func fetch(accessToken: String) async throws -> UsageSnapshot {
        var request = URLRequest(url: Self.endpoint)
        request.timeoutInterval = 15
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ClaudeBar", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200:
            return try UsageSnapshot.parse(data)
        case 401, 403:
            throw ClaudeBarError.usageUnauthorized
        default:
            throw ClaudeBarError.commandFailed("Usage request failed (HTTP \(status)).")
        }
    }
}
