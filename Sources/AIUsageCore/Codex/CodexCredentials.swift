import Foundation

public enum CodexCredentials {
    private struct Auth: Decodable {
        var auth_mode: String?
        var tokens: Tokens?
        struct Tokens: Decodable { var access_token: String?; var account_id: String? }
    }
    public static func load(homeDir: URL, now: Date = .now) throws -> Credential {
        guard let data = try? Data(contentsOf: homeDir.appendingPathComponent("auth.json")) else { throw CredentialError.missing }
        return try decode(data, now: now)
    }
    public static func decode(_ data: Data, now: Date = .now) throws -> Credential {
        guard let auth = try? JSONDecoder().decode(Auth.self, from: data) else { throw CredentialError.malformed }
        guard auth.auth_mode == nil || auth.auth_mode == "chatgpt" else { throw CredentialError.unsupportedAuthMode }
        guard let tokens = auth.tokens, let token = tokens.access_token else { throw CredentialError.missing }
        return try Credential(accessToken: token, accountID: tokens.account_id, expiresAt: expiration(of: token)).validated(now: now)
    }
    // This only reads an expiry hint. Authentication and refresh belong to Codex.
    public static func expiration(of jwt: String) -> Date? {
        let pieces = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 3 else { return nil }
        var payload = String(pieces[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        struct Claims: Decodable { var exp: Double? }
        guard let data = Data(base64Encoded: payload), let claims = try? JSONDecoder().decode(Claims.self, from: data),
              let exp = claims.exp, exp.isFinite else { return nil }
        return Date(timeIntervalSince1970: exp)
    }
}
