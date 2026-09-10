import Foundation
import Testing
@testable import AIUsageCore

@Test func quotaDecodersHandleNullableFieldsAndWindowOrder() throws {
    let claude = try ClaudeQuotaClient.decode(fixture("claude-quota.json"), asOf: testNow, planType: "max")
    #expect(claude.fiveHour?.usedPercent == 33)
    #expect(claude.weekly?.usedPercent == 47.5)
    #expect(claude.weekly?.resetsAt == nil)
    #expect(claude.extra.map(\.name) == ["Sonnet"])
    #expect(claude.planType == "max")
    let codex = try CodexQuotaClient.decode(fixture("codex-quota.json"), asOf: testNow)
    #expect(codex.weekly?.usedPercent == 27)
    #expect(codex.fiveHour?.usedPercent == 12)
    #expect(codex.fiveHour?.resetsAt == testNow.addingTimeInterval(1200))
    #expect(codex.planType == "prolite")
    let empty = try CodexQuotaClient.decode(Data("{\"plan_type\":null,\"rate_limit\":null,\"credits\":null}".utf8), asOf: testNow)
    #expect(empty.fiveHour == nil && empty.weekly == nil)
    let weeklyOnly = Data("{\"rate_limit\":{\"primary_window\":{\"used_percent\":32,\"limit_window_seconds\":604800}}}".utf8)
    #expect(try CodexQuotaClient.decode(weeklyOnly, asOf: testNow).fiveHour == nil)
    #expect(throws: QuotaError.badResponse(statusCode: 200)) { try ClaudeQuotaClient.decode(Data("invalid".utf8), asOf: testNow) }
}

@Test func retryAfterAndHTTPStatusMapping() throws {
    #expect(QuotaHTTP.retryAfter("120", now: testNow) == testNow.addingTimeInterval(120))
    let expected = try #require(TimestampParser.parse("2026-09-10T18:00:00.000Z"))
    #expect(QuotaHTTP.retryAfter("Thu, 10 Sep 2026 18:00:00 GMT", now: testNow) == expected)
    #expect(QuotaHTTP.retryAfter("nonsense", now: testNow) == nil)
    #expect(QuotaHTTP.retryAfter("-1", now: testNow) == testNow)
    #expect(throws: QuotaError.unauthorized) { try QuotaHTTP.validate(HTTPResponse(data: Data(), statusCode: 401)) }
    #expect(throws: QuotaError.rateLimited(retryAfter: testNow.addingTimeInterval(900))) {
        try QuotaHTTP.validate(HTTPResponse(data: Data(), statusCode: 429, headers: ["Retry-After": "900"]), now: testNow)
    }
    #expect(throws: QuotaError.badResponse(statusCode: 503)) { try QuotaHTTP.validate(HTTPResponse(data: Data(), statusCode: 503)) }
}

@Test func refreshPolicyBacksOffHonorsServerAndPersists() throws {
    var policy = RefreshPolicy()
    var now = testNow
    #expect(policy.canAttempt(now: now))
    for delay in [300.0, 600, 1200, 2400, 3600, 3600] {
        policy.beganAttempt(at: now)
        policy.failed(.rateLimited(retryAfter: nil), at: now, jitter: 1)
        #expect(policy.nextAutomaticAttempt == now.addingTimeInterval(delay))
        #expect(!policy.canAttempt(now: now.addingTimeInterval(60), manual: true))
        now = policy.nextAutomaticAttempt
    }
    policy.beganAttempt(at: now)
    policy.failed(.rateLimited(retryAfter: now.addingTimeInterval(7200)), at: now, jitter: 1)
    #expect(policy.nextAutomaticAttempt == now.addingTimeInterval(7200))
    let restored = try JSONDecoder().decode(RefreshPolicy.self, from: JSONEncoder().encode(policy))
    #expect(!restored.canAttempt(now: now.addingTimeInterval(7000), manual: true))
    now = policy.nextAutomaticAttempt
    policy.beganAttempt(at: now)
    policy.succeeded(at: now)
    #expect(policy.rateLimitFailures == 0)
    #expect(!policy.canAttempt(now: now.addingTimeInterval(59), manual: true))
    #expect(policy.canAttempt(now: now.addingTimeInterval(60), manual: true))
    #expect(!policy.canAttempt(now: now.addingTimeInterval(299)))
    for delay in [300.0, 600, 900, 900] {
        now = policy.nextAutomaticAttempt
        policy.beganAttempt(at: now)
        policy.failed(.transport, at: now, jitter: 1)
        #expect(policy.nextAutomaticAttempt == now.addingTimeInterval(delay))
    }
}

@Test func credentialsDecodeExpiryWithoutRefreshing() throws {
    let claude = Data("{\"claudeAiOauth\":{\"accessToken\":\"synthetic-token\",\"expiresAt\":1789041660000,\"subscriptionType\":\"max\"}}".utf8)
    #expect(try ClaudeCredentials.decode(claude, now: testNow).planType == "max")
    #expect(throws: CredentialError.expired) { try ClaudeCredentials.decode(claude, now: testNow.addingTimeInterval(61)) }
    let claims = Data("{\"exp\":1789041660}".utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
    let jwt = "header.\(claims).signature"
    let codex = try JSONSerialization.data(withJSONObject: ["auth_mode": "chatgpt", "tokens": ["access_token": jwt, "account_id": "test-account"]])
    let credential = try CodexCredentials.decode(codex, now: testNow)
    #expect(credential.accountID == "test-account")
    #expect(credential.expiresAt == testNow.addingTimeInterval(60))
    #expect(throws: CredentialError.expired) { try CodexCredentials.decode(codex, now: testNow.addingTimeInterval(60)) }
    #expect(throws: CredentialError.unsupportedAuthMode) { try CodexCredentials.decode(Data("{\"auth_mode\":\"apikey\"}".utf8)) }
    #expect(CodexCredentials.expiration(of: "bad.jwt") == nil)
}

private actor RecordingTransport: QuotaTransport {
    let response: HTTPResponse
    var requests: [URLRequest] = []
    init(_ response: HTTPResponse) { self.response = response }
    func send(_ request: URLRequest) async throws -> HTTPResponse { requests.append(request); return response }
}

@Test func quotaClientsUseCorrectHeadersAndSkipExpiredCredentials() async throws {
    let transport = RecordingTransport(HTTPResponse(data: try fixture("codex-quota.json"), statusCode: 200))
    let client = CodexQuotaClient(transport: transport)
    let credential = Credential(accessToken: "test-token", accountID: "test-account")
    _ = try await client.fetchQuota(credential: credential)
    let requests = await transport.requests
    #expect(requests.count == 1)
    #expect(requests[0].url?.path == "/backend-api/wham/usage")
    #expect(requests[0].httpMethod == "GET")
    #expect(requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
    #expect(requests[0].value(forHTTPHeaderField: "ChatGPT-Account-Id") == "test-account")
    await #expect(throws: CredentialError.expired) {
        try await client.fetchQuota(credential: Credential(accessToken: "expired", expiresAt: .distantPast))
    }
    #expect(await transport.requests.count == 1)
    let claudeTransport = RecordingTransport(HTTPResponse(data: try fixture("claude-quota.json"), statusCode: 200))
    _ = try await ClaudeQuotaClient(transport: claudeTransport).fetchQuota(credential: credential)
    #expect(await claudeTransport.requests.first?.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
}

@Test func newestQuotaUsesTimestampAndPreservesSource() {
    let network = QuotaSnapshot(provider: .codex, asOf: testNow, source: .network)
    let local = QuotaSnapshot(provider: .codex, asOf: testNow.addingTimeInterval(30), source: .localLog)
    let cache = QuotaSnapshot(provider: .codex, asOf: testNow.addingTimeInterval(-30), source: .diskCache)
    #expect(QuotaSnapshot.newest([network, local, cache]) == local)
    let tiedCache = QuotaSnapshot(provider: .codex, asOf: testNow, source: .diskCache)
    #expect(QuotaSnapshot.newest([network, tiedCache]) == network)
}
