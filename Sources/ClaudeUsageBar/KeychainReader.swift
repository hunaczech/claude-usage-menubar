import Foundation
import Security

/// Errors surfaced by credential access, kept distinct so the UI can show an
/// actionable message ("Open Claude Code to re-auth") instead of crashing.
enum CredentialError: LocalizedError {
    case notFound
    case malformed
    case refreshFailed(String)

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "No Claude Code credentials found in Keychain. Sign in with Claude Code first."
        case .malformed:
            return "Claude Code credentials are in an unexpected format."
        case .refreshFailed(let detail):
            return "Couldn't refresh the access token (\(detail)). Open Claude Code to re-auth."
        }
    }
}

/// Decoded OAuth credentials as written by Claude Code.
struct Credentials {
    let accessToken: String
    let refreshToken: String
    /// Absolute expiry of `accessToken`.
    let expiresAt: Date
}

/// Reads the OAuth token Claude Code stores in the macOS login Keychain and,
/// when it has expired, mints a fresh one via the refresh-token grant.
///
/// The token is only ever held in memory and only ever sent to Anthropic
/// hosts — it is never written back to the Keychain (to avoid corrupting
/// Claude Code's own entry) and never logged.
actor KeychainReader {

    // Service name Claude Code uses for its generic-password Keychain item.
    private static let service = "Claude Code-credentials"
    // Claude Code's public OAuth client id (used for the refresh grant).
    private static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static let tokenEndpoint = URL(string: "https://console.anthropic.com/v1/oauth/token")!

    // In-memory cache of a token we refreshed ourselves this session.
    private var cachedAccessToken: String?
    private var cachedExpiresAt: Date?

    /// Returns a currently-valid access token, refreshing if necessary.
    func validAccessToken() async throws -> String {
        // Prefer a still-valid token we already refreshed this session.
        if let token = cachedAccessToken, let exp = cachedExpiresAt, exp > Date().addingTimeInterval(60) {
            return token
        }

        let creds = try readCredentials()
        if creds.expiresAt > Date().addingTimeInterval(60) {
            return creds.accessToken
        }

        // Expired (or about to) — refresh.
        let refreshed = try await refresh(using: creds.refreshToken)
        cachedAccessToken = refreshed.accessToken
        cachedExpiresAt = refreshed.expiresAt
        return refreshed.accessToken
    }

    /// Reads and decodes the credentials JSON from the Keychain.
    func readCredentials() throws -> Credentials {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            throw CredentialError.notFound
        }

        return try Self.decode(data)
    }

    /// Parses the `{ "claudeAiOauth": { accessToken, refreshToken, expiresAt } }`
    /// shape Claude Code writes. `expiresAt` is epoch milliseconds.
    static func decode(_ data: Data) throws -> Credentials {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let oauth = root["claudeAiOauth"] as? [String: Any],
            let accessToken = oauth["accessToken"] as? String,
            let refreshToken = oauth["refreshToken"] as? String
        else {
            throw CredentialError.malformed
        }

        // expiresAt may arrive as a number or a numeric string (epoch ms).
        let expiresMs: Double
        if let n = oauth["expiresAt"] as? Double {
            expiresMs = n
        } else if let s = oauth["expiresAt"] as? String, let n = Double(s) {
            expiresMs = n
        } else {
            // No expiry available — assume valid and let a 401 trigger refresh.
            expiresMs = Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000
        }

        return Credentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date(timeIntervalSince1970: expiresMs / 1000)
        )
    }

    /// Runs the OAuth refresh-token grant and returns the new access token.
    private func refresh(using refreshToken: String) async throws -> (accessToken: String, expiresAt: Date) {
        var request = URLRequest(url: Self.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        let body: [String: Any] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": Self.clientID
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw CredentialError.refreshFailed(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw CredentialError.refreshFailed("HTTP \(code)")
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let accessToken = json["access_token"] as? String
        else {
            throw CredentialError.refreshFailed("unexpected token response")
        }

        let expiresIn = (json["expires_in"] as? Double) ?? 3600
        return (accessToken, Date().addingTimeInterval(expiresIn))
    }
}
