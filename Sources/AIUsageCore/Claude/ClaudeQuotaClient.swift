import Foundation

public struct ClaudeQuotaClient: UsageProvider {
    public let id = Provider.claude
    public let homeDir: URL
    public var logRoot: URL { homeDir.appendingPathComponent("projects", isDirectory: true) }
    private let transport: any QuotaTransport
    public init(homeDir: URL = AppPaths().claudeHome, transport: any QuotaTransport = URLSessionQuotaTransport()) {
        self.homeDir = homeDir; self.transport = transport
    }
    public func loadCredential() async throws -> Credential { try ClaudeCredentials.load(homeDir: homeDir) }
    public func fetchQuota(credential: Credential) async throws -> QuotaSnapshot {
        _ = try credential.validated()
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let response = try await transport.send(request)
        try QuotaHTTP.validate(response)
        return try Self.decode(response.data, asOf: .now, planType: credential.planType)
    }
    public static func decode(_ data: Data, asOf: Date, planType: String? = nil) throws -> QuotaSnapshot {
        guard let dto = try? JSONDecoder().decode(Response.self, from: data) else { throw QuotaError.badResponse(statusCode: 200) }
        var extra: [ExtraQuotaWindow] = []
        if let window = dto.seven_day_opus?.window(seconds: 604800) { extra.append(.init(name: "Opus", window: window)) }
        if let window = dto.seven_day_sonnet?.window(seconds: 604800) { extra.append(.init(name: "Sonnet", window: window)) }
        return QuotaSnapshot(provider: .claude, fiveHour: dto.five_hour?.window(seconds: 18000),
                             weekly: dto.seven_day?.window(seconds: 604800), extra: extra,
                             planType: planType, asOf: asOf, source: .network)
    }
    private struct Response: Decodable {
        var five_hour: Window?
        var seven_day: Window?
        var seven_day_opus: Window?
        var seven_day_sonnet: Window?
    }
    private struct Window: Decodable {
        var utilization: Double?
        var resets_at: String?
        func window(seconds: Int) -> QuotaWindow? {
            utilization.map { QuotaWindow(usedPercent: $0, resetsAt: resets_at.flatMap(TimestampParser.parse), windowLength: seconds) }
        }
    }
}
