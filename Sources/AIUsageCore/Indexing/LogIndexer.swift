import Foundation

public actor LogIndexer {
    private let roots: [Provider: URL]
    private let stateURL: URL
    private var state = IndexState()
    private var loaded = false
    private var listeners: [UUID: AsyncStream<IndexProgress>.Continuation] = [:]
    private var lastProgressPublication = Date.distantPast
    private let claudeParser = ClaudeLogParser()
    private let codexParser = CodexLogParser()
    private static let assistant = Array("\"assistant\"".utf8)
    private static let tokenCount = Array("\"token_count\"".utf8)
    private static let turnContext = Array("\"turn_context\"".utf8)

    public init(roots: [Provider: URL], stateURL: URL) { self.roots = roots; self.stateURL = stateURL }
    public init(paths: AppPaths = AppPaths()) {
        roots = [.claude: paths.claudeHome.appendingPathComponent("projects"), .codex: paths.codexHome.appendingPathComponent("sessions")]
        stateURL = paths.indexState
    }

    public func progressUpdates() -> AsyncStream<IndexProgress> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<IndexProgress>.makeStream(bufferingPolicy: .bufferingNewest(1))
        listeners[id] = continuation
        continuation.onTermination = { [weak self] _ in Task { await self?.removeListener(id) } }
        return stream
    }
    private func removeListener(_ id: UUID) { listeners.removeValue(forKey: id) }
    private func publish(_ progress: IndexProgress) {
        let now = Date.now
        guard !progress.isRunning || progress.completedFiles == 0 || progress.completedFiles == progress.totalFiles
                || now.timeIntervalSince(lastProgressPublication) >= 0.1 else { return }
        lastProgressPublication = now
        for listener in listeners.values { listener.yield(progress) }
    }

    public func cachedResult() -> IndexResult {
        loadIfNeeded()
        return result()
    }
    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        if let cached = try? AppSupport.read(IndexState.self, from: stateURL), cached.schemaVersion == IndexState.currentSchemaVersion {
            state = cached
        }
    }

    public func refresh(forceRebuild: Bool = false) throws -> IndexResult {
        try autoreleasepool { try performRefresh(forceRebuild: forceRebuild) }
    }

    private func performRefresh(forceRebuild: Bool) throws -> IndexResult {
        loadIfNeeded()
        let files = enumerateFiles()
        let changedIdentity = files.contains { file in
            guard let old = state.files[file.url.path] else { return false }
            return file.size < old.size || file.size < old.offset || file.identity != old.identity
                || (file.size == old.size && file.modifiedAt != old.modifiedAt)
        }
        if forceRebuild || changedIdentity || !FileManager.default.fileExists(atPath: stateURL.path) { state = IndexState() }
        var progress = IndexProgress()
        progress.isRebuilding = !state.isComplete
        progress.isRunning = true
        progress.totalFiles = files.count
        progress.totalBytes = files.reduce(0) { $0 + ($1.size - min($1.size, state.files[$1.url.path]?.offset ?? 0)) }
        publish(progress)
        defer { progress.isRunning = false; publish(progress) }
        var dirty = !state.isComplete
        var unreadable = 0
        var sinceCheckpoint = 0
        for file in files {
            try Task.checkCancellation()
            defer { progress.completedFiles += 1; publish(progress) }
            let old = state.files[file.url.path]
            if let old, old.size == file.size, old.modifiedAt == file.modifiedAt { continue }
            var parserState = old?.parserState ?? CodexParserState()
            // Commit each file together with its offset, so a read failure cannot double count on retry.
            var additions: [String: HourlyBucket] = [:]
            var newKeys: Set<String> = []
            var newest: QuotaSnapshot?
            var malformed = 0
            let read: LineReadResult
            do {
                read = try LineReader.read(file.url, fromOffset: old?.offset ?? 0, throughOffset: file.size) { bytes in
                    let relevant = file.provider == .claude
                        ? LineReader.contains(bytes, Self.assistant)
                        : (LineReader.contains(bytes, Self.tokenCount) || LineReader.contains(bytes, Self.turnContext))
                    guard relevant else { return }
                    autoreleasepool {
                        do {
                            let event: TokenEvent?
                            if file.provider == .claude {
                                event = try claudeParser.parse(Data(bytes))
                            } else {
                                let parsed = try codexParser.parse(Data(bytes), state: &parserState)
                                event = parsed.event
                                newest = QuotaSnapshot.newest([newest, parsed.quota])
                            }
                            guard let event else { return }
                            if let key = event.deduplicationKey {
                                guard !state.seenClaudeKeys.contains(key), newKeys.insert(key).inserted else { return }
                            }
                            let hour = Aggregation.hour(containing: event.date)
                            let key = "\(Int(hour.timeIntervalSince1970))|\(event.provider.rawValue)|\(event.model)"
                            if additions[key] == nil {
                                additions[key] = HourlyBucket(hour: hour, provider: event.provider, model: event.model, totals: TokenTotals())
                            }
                            additions[key]?.totals += event.totals
                        } catch { malformed += 1 }
                    }
                }
            } catch {
                unreadable += 1
                continue
            }
            for (key, bucket) in additions {
                if state.buckets[key] == nil { state.buckets[key] = bucket }
                else { state.buckets[key]?.totals += bucket.totals }
            }
            state.seenClaudeKeys.formUnion(newKeys)
            state.newestCodexRateLimits = QuotaSnapshot.newest([state.newestCodexRateLimits, newest])
            state.malformedLines += malformed + read.oversizedLines
            state.files[file.url.path] = IndexedFile(offset: read.offset, size: file.size, modifiedAt: file.modifiedAt,
                                                     identity: file.identity, parserState: parserState)
            progress.bytesRead += read.bytesRead
            dirty = true
            sinceCheckpoint += 1
            if progress.isRebuilding && sinceCheckpoint >= 50 {
                try AppSupport.write(state, to: stateURL)
                sinceCheckpoint = 0
            }
        }
        state.isComplete = unreadable == 0
        state.lastIndexedAt = .now
        if dirty { try AppSupport.write(state, to: stateURL) }
        AppSupport.logger.info("Indexed \(files.count) files; read \(progress.bytesRead) bytes; skipped \(self.state.malformedLines) malformed rows")
        return result(bytesRead: progress.bytesRead, unreadable: unreadable)
    }

    private func result(bytesRead: UInt64 = 0, unreadable: Int = 0) -> IndexResult {
        IndexResult(buckets: Array(state.buckets.values), localQuota: state.newestCodexRateLimits,
                    malformedLines: state.malformedLines, unreadableFiles: unreadable,
                    bytesRead: bytesRead, indexedAt: state.lastIndexedAt)
    }
    private struct File: Sendable { var provider: Provider; var url: URL; var size: UInt64; var modifiedAt: Date; var identity: UInt64 }
    private func enumerateFiles() -> [File] {
        var files: [File] = []
        for (provider, root) in roots {
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey],
                                                                   options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                      attributes[.type] as? FileAttributeType == .typeRegular,
                      let size = attributes[.size] as? UInt64, let modifiedAt = attributes[.modificationDate] as? Date else { continue }
                files.append(File(provider: provider, url: url, size: size, modifiedAt: modifiedAt,
                                  identity: attributes[.systemFileNumber] as? UInt64 ?? 0))
            }
        }
        return files.sorted { $0.url.path < $1.url.path }
    }
}
