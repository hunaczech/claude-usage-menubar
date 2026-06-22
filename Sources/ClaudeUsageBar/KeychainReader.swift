import Foundation
import Security

/// Errors surfaced by credential access, kept distinct so the UI can show an
/// actionable message ("Open Claude Code to re-auth") instead of crashing.
enum CredentialError: LocalizedError {
    case notFound
    case malformed

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "No Claude Code credentials found in Keychain. Sign in with Claude Code first."
        case .malformed:
            return "Claude Code credentials are in an unexpected format."
        }
    }
}

/// Decoded OAuth credentials as written by Claude Code.
struct Credentials {
    let accessToken: String
}

/// Reads the OAuth token Claude Code stores in the macOS login Keychain.
///
/// We deliberately do **not** refresh the token ourselves. Claude Code owns the
/// credential and keeps it fresh; if we ran the refresh-token grant and Anthropic
/// rotates refresh tokens, we'd invalidate Claude Code's stored copy and could log
/// the user out of Claude Code. Instead, an expired token simply yields a 401 from
/// the usage request, which the UI turns into "Open Claude Code to re-auth".
///
/// The token is only ever held in memory, only ever sent to Anthropic hosts, and
/// never written back to the Keychain or logged.
actor KeychainReader {

    // Service name Claude Code uses for its generic-password Keychain item.
    private static let service = "Claude Code-credentials"

    /// Returns the stored access token. An expired token is returned as-is; the
    /// caller's request will 401 and surface a re-auth prompt.
    func validAccessToken() async throws -> String {
        try readCredentials().accessToken
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

    /// Parses the `{ "claudeAiOauth": { accessToken, ... } }` shape Claude Code writes.
    static func decode(_ data: Data) throws -> Credentials {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let oauth = root["claudeAiOauth"] as? [String: Any],
            let accessToken = oauth["accessToken"] as? String
        else {
            throw CredentialError.malformed
        }

        return Credentials(accessToken: accessToken)
    }
}
