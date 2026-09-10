import Foundation
import Testing
@testable import AIUsageCore

private actor ProviderProbe {
    var fetches = 0
    func fetched() { fetches += 1 }
}
private struct StubProvider: UsageProvider {
    var id: Provider = .codex
    var homeDir: URL
    var logRoot: URL { homeDir.appendingPathComponent("sessions") }
    var probe: ProviderProbe
    var credential: Credential = Credential(accessToken: "synthetic-token")
    var failure: QuotaError?
    var local: QuotaSnapshot?
    func loadCredential() async throws -> Credential { try credential.validated() }
    func localQuotaSnapshot() async -> QuotaSnapshot? { local }
    func fetchQuota(credential: Credential) async throws -> QuotaSnapshot {
        await probe.fetched()
        if let failure { throw failure }
        return QuotaSnapshot(provider: id, weekly: QuotaWindow(usedPercent: 32, windowLength: 604800), asOf: .now, source: .network)
    }
}

@MainActor private func waitForRefresh(_ store: UsageStore) async throws {
    for _ in 0..<200 {
        if store.lastLogRefresh != nil && !store.isRefreshing && store.state(for: .codex).status != .loading { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Store did not complete initial refresh")
}

@Test @MainActor func unauthorizedKeepsNewestLocalQuotaAndDoesNotSpamRequests() async throws {
    let dir = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let paths = AppPaths(home: dir, environment: [:], support: dir.appendingPathComponent("support"))
    let probe = ProviderProbe()
    let local = QuotaSnapshot(provider: .codex, weekly: QuotaWindow(usedPercent: 31, windowLength: 604800), asOf: .now, source: .localLog)
    let provider = StubProvider(homeDir: dir, probe: probe, failure: .unauthorized, local: local)
    var cache = QuotaCache()
    cache.snapshots[.codex] = QuotaSnapshot(provider: .codex, weekly: QuotaWindow(usedPercent: 10, windowLength: 604800),
                                         asOf: .now.addingTimeInterval(-600), source: .network)
    try AppSupport.write(cache, to: paths.quotaCache)
    let store = UsageStore(paths: paths, clients: [provider])
    store.start()
    defer { store.stop() }
    try await waitForRefresh(store)
    #expect(store.state(for: .codex).quota?.weekly?.usedPercent == 31)
    #expect(store.state(for: .codex).status == .expired)
    #expect(await probe.fetches == 1)
    store.refreshNow()
    try await Task.sleep(for: .milliseconds(30))
    #expect(await probe.fetches == 1)
    #expect(store.menuBarText == "– · 31%")
    let persisted = try AppSupport.read(QuotaCache.self, from: paths.quotaCache)
    #expect(persisted.snapshots[.codex]?.weekly?.usedPercent == 31)
    #expect(!String(decoding: try Data(contentsOf: paths.quotaCache), as: UTF8.self).contains("synthetic-token"))
}

@Test @MainActor func expiredCredentialNeverReachesTransport() async throws {
    let dir = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let paths = AppPaths(home: dir, environment: [:], support: dir.appendingPathComponent("support"))
    let probe = ProviderProbe()
    let provider = StubProvider(homeDir: dir, probe: probe, credential: Credential(accessToken: "expired", expiresAt: .distantPast))
    let store = UsageStore(paths: paths, clients: [provider])
    store.start()
    defer { store.stop() }
    try await waitForRefresh(store)
    #expect(store.state(for: .codex).status == .expired)
    #expect(await probe.fetches == 0)
}

@Test @MainActor func savedRetryAfterSurvivesAppRestart() async throws {
    let dir = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let paths = AppPaths(home: dir, environment: [:], support: dir.appendingPathComponent("support"))
    let probe = ProviderProbe()
    let provider = StubProvider(homeDir: dir, probe: probe)
    var cache = QuotaCache()
    var policy = RefreshPolicy()
    let now = Date.now
    let until = now.addingTimeInterval(7200)
    policy.beganAttempt(at: now)
    policy.failed(.rateLimited(retryAfter: until), at: now, jitter: 1)
    cache.policies[.codex] = policy
    try AppSupport.write(cache, to: paths.quotaCache)
    let store = UsageStore(paths: paths, clients: [provider])
    store.start()
    defer { store.stop() }
    try await waitForRefresh(store)
    #expect(store.state(for: .codex).status == .rateLimited(until: until))
    store.refreshNow()
    try await Task.sleep(for: .milliseconds(30))
    #expect(await probe.fetches == 0)
}

@Test @MainActor func offlineKeepsCachedQuotaAndMissingToolsDoNotPoll() async throws {
    let dir = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let paths = AppPaths(home: dir, environment: [:], support: dir.appendingPathComponent("support"))
    let probe = ProviderProbe()
    var cache = QuotaCache()
    cache.snapshots[.codex] = QuotaSnapshot(provider: .codex, weekly: QuotaWindow(usedPercent: 25, windowLength: 604800),
                                         asOf: .now.addingTimeInterval(-600), source: .network)
    try AppSupport.write(cache, to: paths.quotaCache)
    let offline = UsageStore(paths: paths, clients: [StubProvider(homeDir: dir, probe: probe, failure: .transport)])
    offline.start()
    defer { offline.stop() }
    try await waitForRefresh(offline)
    #expect(offline.state(for: .codex).status == .offline)
    #expect(offline.state(for: .codex).quota?.weekly?.usedPercent == 25)
    #expect(offline.state(for: .codex).quota?.source == .diskCache)
    let missingProbe = ProviderProbe()
    let missing = UsageStore(paths: paths, clients: [StubProvider(homeDir: dir.appendingPathComponent("missing"), probe: missingProbe)])
    missing.start()
    defer { missing.stop() }
    try await waitForRefresh(missing)
    #expect(missing.state(for: .codex).status == .notInstalled)
    #expect(await missingProbe.fetches == 0)
}
