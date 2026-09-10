import Foundation

public struct CodexQuotaClient: UsageProvider {
    public let id = Provider.codex
    public let homeDir: URL
    public var logRoot: URL { homeDir.appendingPathComponent("sessions", isDirectory: true) }
    private let transport: any QuotaTransport
    public init(homeDir: URL = AppPaths().codexHome, transport: any QuotaTransport = URLSessionQuotaTransport()) {
        self.homeDir = homeDir; self.transport = transport
    }
    public func loadCredential() async throws -> Credential { try CodexCredentials.load(homeDir: homeDir) }
    public func localQuotaSnapshot() async -> QuotaSnapshot? { autoreleasepool { CodexLogParser.newestSnapshot(in: logRoot) } }
    public func fetchQuota(credential: Credential) async throws -> QuotaSnapshot {
        _ = try credential.validated()
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        if let accountID = credential.accountID { request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id") }
        request.setValue("AIUsage/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        let response = try await transport.send(request)
        try QuotaHTTP.validate(response)
        return try Self.decode(response.data, asOf: .now)
    }
    public static func decode(_ data: Data, asOf: Date) throws -> QuotaSnapshot {
        guard let dto = try? JSONDecoder().decode(Response.self, from: data) else { throw QuotaError.badResponse(statusCode: 200) }
        var result = QuotaSnapshot(provider: .codex, planType: dto.plan_type, asOf: asOf, source: .network)
        for dtoWindow in [dto.rate_limit?.primary_window, dto.rate_limit?.secondary_window].compactMap({ $0 }) {
            guard let percent = dtoWindow.used_percent, let seconds = dtoWindow.limit_window_seconds else { continue }
            let reset = dtoWindow.reset_at.map { Date(timeIntervalSince1970: $0) }
                ?? dtoWindow.reset_after_seconds.map { asOf.addingTimeInterval(max(0, $0)) }
            let window = QuotaWindow(usedPercent: percent, resetsAt: reset, windowLength: seconds)
            if seconds == 18000 { result.fiveHour = window }
            else if seconds == 604800 { result.weekly = window }
        }
        return result
    }
    private struct Response: Decodable { var plan_type: String?; var rate_limit: RateLimit? }
    private struct RateLimit: Decodable { var primary_window: Window?; var secondary_window: Window? }
    private struct Window: Decodable {
        var used_percent: Double?
        var limit_window_seconds: Int?
        var reset_after_seconds: Double?
        var reset_at: Double?
    }
}
