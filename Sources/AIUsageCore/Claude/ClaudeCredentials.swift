import Foundation

public enum ClaudeCredentials {
    private struct Envelope: Decodable {
        var claudeAiOauth: OAuth?
        struct OAuth: Decodable {
            var accessToken: String?
            var expiresAt: Double?
            var subscriptionType: String?
        }
    }

    public static func decode(_ data: Data, now: Date = .now) throws -> Credential {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              let oauth = envelope.claudeAiOauth, let token = oauth.accessToken else { throw CredentialError.malformed }
        return try Credential(accessToken: token, expiresAt: oauth.expiresAt.map { Date(timeIntervalSince1970: $0 / 1000) },
                              planType: oauth.subscriptionType).validated(now: now)
    }

    public static func load(homeDir: URL, environment: [String: String] = ProcessInfo.processInfo.environment,
                            now: Date = .now) throws -> Credential {
        var failure: CredentialError = .missing
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-a", NSUserName(), "-s", "Claude Code-credentials", "-w"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                do { return try decode(data, now: now) }
                catch let error as CredentialError { failure = error }
            }
        } catch { /* Try the file and environment if Keychain is unavailable. */ }
        let file = homeDir.appendingPathComponent(".credentials.json")
        if let data = try? Data(contentsOf: file) {
            do { return try decode(data, now: now) }
            catch let error as CredentialError { failure = error }
        }
        if let token = environment["CLAUDE_CODE_OAUTH_TOKEN"], !token.isEmpty {
            return Credential(accessToken: token)
        }
        throw failure
    }
}
