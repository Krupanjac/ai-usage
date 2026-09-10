import Foundation
import Observation

@MainActor @Observable
public final class UsageStore {
    public private(set) var providers: [Provider: ProviderState] = Dictionary(uniqueKeysWithValues: Provider.allCases.map { ($0, ProviderState(provider: $0)) })
    public private(set) var buckets: [HourlyBucket] = []
    public private(set) var indexProgress = IndexProgress()
    public private(set) var lastLogRefresh: Date?
    public private(set) var indexMessage: String?
    public private(set) var cacheMessage: String?
    public var selectedProvider: Provider = .claude
    public var chartRange: ChartRange = .fortnight
    @ObservationIgnored private let clients: [any UsageProvider]
    @ObservationIgnored private let indexer: LogIndexer
    @ObservationIgnored private let cacheStore: QuotaCacheStore
    @ObservationIgnored private var cache = QuotaCache()
    @ObservationIgnored private var rejectedTokens: [Provider: String] = [:]
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var started = false
    @ObservationIgnored private var ready = false
    @ObservationIgnored private var indexing = false

    public init(paths: AppPaths = AppPaths(), clients: [any UsageProvider]? = nil, indexer: LogIndexer? = nil) {
        self.clients = clients ?? [ClaudeQuotaClient(homeDir: paths.claudeHome), CodexQuotaClient(homeDir: paths.codexHome)]
        self.indexer = indexer ?? LogIndexer(paths: paths)
        self.cacheStore = QuotaCacheStore(url: paths.quotaCache)
    }
    public var menuBarText: String {
        Provider.allCases.map { id in
            providers[id]?.quota?.maximumPercent.map { "\(Int($0.rounded()))%" } ?? "–"
        }.joined(separator: " · ")
    }
    public var isRefreshing: Bool { providers.values.contains { $0.isRefreshing } }
    public var lastQuotaRefresh: Date? { providers.values.compactMap { $0.quota?.asOf }.max() }
    public func state(for provider: Provider) -> ProviderState { providers[provider] ?? ProviderState(provider: provider) }
    public func chartSeries(now: Date = .now) -> [DailyUsage] {
        Aggregation.series(buckets: buckets, provider: selectedProvider, range: chartRange, now: now)
    }
    public func start() {
        guard !started else { return }
        started = true
        tasks.append(Task { [weak self] in await self?.bootstrap() })
    }
    public func stop() {
        for task in tasks { task.cancel() }
        tasks.removeAll()
        started = false
        ready = false
    }
    private func bootstrap() async {
        cache = await cacheStore.load()
        guard !Task.isCancelled else { return }
        for client in clients {
            providers[client.id]?.quota = cache.snapshots[client.id]
            providers[client.id]?.status = client.isInstalled ? .available : .notInstalled
        }
        let updates = await indexer.progressUpdates()
        tasks.append(Task { [weak self] in
            for await progress in updates {
                guard !Task.isCancelled else { break }
                self?.indexProgress = progress
            }
        })
        applyIndex(await indexer.cachedResult())
        ready = true
        for client in clients {
            tasks.append(Task { [weak self] in
                if client.isInstalled, let local = await client.localQuotaSnapshot() { self?.consider(local) }
                while !Task.isCancelled {
                    await self?.refreshQuota(client, manual: false)
                    do { try await Task.sleep(for: .seconds(30)) } catch { break }
                }
            })
        }
        tasks.append(Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshLogs()
                do { try await Task.sleep(for: .seconds(60)) } catch { break }
            }
        })
    }
    public func popoverOpened() {
        start()
        guard ready, lastLogRefresh.map({ Date.now.timeIntervalSince($0) > 30 }) ?? true else { return }
        Task { [weak self] in await self?.refreshLogs() }
    }
    public func refreshNow() {
        guard ready else { start(); return }
        for client in clients { Task { [weak self] in await self?.refreshQuota(client, manual: true) } }
        Task { [weak self] in await self?.refreshLogs() }
    }
    public func rebuildIndex() {
        guard ready, !indexing else { return }
        Task { [weak self] in await self?.refreshLogs(rebuild: true) }
    }
    private func refreshLogs(rebuild: Bool = false) async {
        guard !indexing else { return }
        indexing = true
        defer { indexing = false }
        do {
            let result = try await indexer.refresh(forceRebuild: rebuild)
            guard !Task.isCancelled else { return }
            applyIndex(result)
            lastLogRefresh = .now
            await saveCache()
        } catch is CancellationError { return }
        catch {
            indexMessage = "History could not be updated. Try rebuilding the index."
            AppSupport.logger.error("History indexing or checkpoint write failed")
        }
    }
    private func applyIndex(_ result: IndexResult) {
        buckets = result.buckets
        if let quota = result.localQuota { consider(quota) }
        if result.unreadableFiles > 0 { indexMessage = "\(result.unreadableFiles) history files could not be read." }
        else if result.malformedLines > 0 { indexMessage = "Skipped \(result.malformedLines) unreadable history rows." }
        else { indexMessage = nil }
    }
    private func consider(_ snapshot: QuotaSnapshot) {
        let newest = QuotaSnapshot.newest([providers[snapshot.provider]?.quota, snapshot])
        providers[snapshot.provider]?.quota = newest
        cache.snapshots[snapshot.provider] = newest
        if providers[snapshot.provider]?.status == .loading { providers[snapshot.provider]?.status = .available }
    }
    private func refreshQuota(_ client: any UsageProvider, manual: Bool) async {
        let id = client.id
        guard client.isInstalled else { providers[id]?.status = .notInstalled; return }
        guard providers[id]?.isRefreshing == false else { return }
        let now = Date.now
        var policy = cache.policies[id] ?? RefreshPolicy()
        guard policy.canAttempt(now: now, manual: manual) else {
            if let until = policy.rateLimitUntil, now < until { providers[id]?.status = .rateLimited(until: until) }
            return
        }
        policy.beganAttempt(at: now)
        cache.policies[id] = policy
        providers[id]?.isRefreshing = true
        providers[id]?.lastAttempt = now
        defer { providers[id]?.isRefreshing = false }
        var credential: Credential?
        do {
            let loaded = try await client.loadCredential()
            _ = try loaded.validated()
            credential = loaded
            guard rejectedTokens[id] != loaded.accessToken else { throw CredentialError.expired }
            let snapshot = try await client.fetchQuota(credential: loaded)
            guard !Task.isCancelled else { return }
            consider(snapshot)
            providers[id]?.status = .available
            rejectedTokens.removeValue(forKey: id)
            policy.succeeded(at: .now)
        } catch is CancellationError { return }
        catch let error as CredentialError {
            providers[id]?.status = error == .expired ? .expired : .signIn
        } catch let error as QuotaError {
            policy.failed(error, at: .now)
            switch error {
            case .unauthorized:
                rejectedTokens[id] = credential?.accessToken
                providers[id]?.status = .expired
            case .rateLimited: providers[id]?.status = .rateLimited(until: policy.nextAutomaticAttempt)
            case .transport: providers[id]?.status = .offline
            case .badResponse: providers[id]?.status = .failed
            }
        } catch {
            policy.failed(.transport, at: .now)
            providers[id]?.status = .offline
        }
        cache.policies[id] = policy
        await saveCache()
    }
    private func saveCache() async {
        do { try await cacheStore.save(cache); cacheMessage = nil }
        catch {
            cacheMessage = "Usage is available, but the local cache could not be saved."
            AppSupport.logger.error("Quota cache write failed")
        }
    }
}
