import Foundation

/// A single utilization snapshot for the two rate-limit windows.
struct Usage: Equatable {
    /// 0–100 percentage for the rolling 5-hour window, if present.
    var fiveHourPct: Double?
    /// 0–100 percentage for the 7-day/weekly window, if present.
    var weeklyPct: Double?
    var fetchedAt: Date

    /// The more binding (higher) of the two windows — what the menu bar headlines.
    var headline: Double? {
        [fiveHourPct, weeklyPct].compactMap { $0 }.max()
    }
}

/// Abstracts where usage comes from so the header-based client can be swapped
/// for the documented CLI fallback without touching the rest of the app.
protocol UsageProviding {
    func fetch() async throws -> Usage
}

enum UsageError: LocalizedError {
    case auth(Int)
    case transport(String)
    case noHeaders

    var errorDescription: String? {
        switch self {
        case .auth(let code):
            return "Authorization failed (HTTP \(code)). Open Claude Code to re-auth."
        case .transport(let detail):
            return "Network error: \(detail)"
        case .noHeaders:
            return "Response carried no utilization headers."
        }
    }
}

/// Fetches utilization by reading the `anthropic-ratelimit-unified-*-utilization`
/// response headers off a minimal 1-token request. Both 200 and 429 responses
/// carry these headers, so 429 is not treated as fatal.
struct HeaderUsageClient: UsageProviding {
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let tokenProvider: () async throws -> String

    /// - Parameter tokenProvider: returns a valid OAuth access token on demand.
    init(tokenProvider: @escaping () async throws -> String) {
        self.tokenProvider = tokenProvider
    }

    func fetch() async throws -> Usage {
        let token = try await tokenProvider()

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 1,
            "messages": [["role": "user", "content": "."]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let response: URLResponse
        do {
            (_, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw UsageError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw UsageError.transport("non-HTTP response")
        }

        // 401/403 mean the token is bad — surface as auth so the UI can prompt
        // re-auth. Everything else (200, 429, even 5xx) still carries headers.
        if http.statusCode == 401 || http.statusCode == 403 {
            throw UsageError.auth(http.statusCode)
        }

        let fiveHour = Self.percentHeader(http, "anthropic-ratelimit-unified-5h-utilization")
        let weekly = Self.percentHeader(http, "anthropic-ratelimit-unified-7d-utilization")

        guard fiveHour != nil || weekly != nil else {
            throw UsageError.noHeaders
        }

        return Usage(fiveHourPct: fiveHour, weeklyPct: weekly, fetchedAt: Date())
    }

    /// Case-insensitive header lookup returning a parsed percentage.
    private static func percentHeader(_ http: HTTPURLResponse, _ name: String) -> Double? {
        let value = http.value(forHTTPHeaderField: name)
        guard let raw = value?.trimmingCharacters(in: .whitespaces), let n = Double(raw) else {
            return nil
        }
        return n
    }
}
