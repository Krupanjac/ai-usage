import Foundation
import Testing
@testable import AIUsageCore

@Test func indexerDeduplicatesAcrossFilesAndRestoresCacheWithoutRereading() async throws {
    let dir = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let claudeRoot = dir.appendingPathComponent("claude")
    let codexRoot = dir.appendingPathComponent("codex")
    let stateURL = dir.appendingPathComponent("state.json")
    try write(fixture("claude.jsonl"), to: claudeRoot.appendingPathComponent("a.jsonl"))
    try write(fixture("claude.jsonl"), to: claudeRoot.appendingPathComponent("session/subagents/b.jsonl"))
    try write(fixture("codex.jsonl"), to: codexRoot.appendingPathComponent("rollout.jsonl"))
    let roots: [Provider: URL] = [.claude: claudeRoot, .codex: codexRoot]
    let indexer = LogIndexer(roots: roots, stateURL: stateURL)
    let cold = try await indexer.refresh()
    #expect(cold.buckets.filter { $0.provider == .claude }.reduce(0) { $0 + $1.totals.total } == 100)
    #expect(cold.buckets.filter { $0.provider == .codex }.reduce(0) { $0 + $1.totals.total } == 175)
    #expect(cold.localQuota?.weekly?.usedPercent == 29)
    #expect(cold.bytesRead > 0)
    #expect(cold.malformedLines == 0)
    let restored = LogIndexer(roots: roots, stateURL: stateURL)
    #expect(await restored.cachedResult().buckets.count == cold.buckets.count)
    let warm = try await restored.refresh()
    #expect(warm.bytesRead == 0)
    #expect(warm.buckets.reduce(0) { $0 + $1.totals.total } == 275)
    let mode = try FileManager.default.attributesOfItem(atPath: stateURL.path)[.posixPermissions] as? Int
    #expect(mode == 0o600)
}

@Test func indexerResumesCodexStateAcrossPartialAppends() async throws {
    let dir = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let root = dir.appendingPathComponent("logs")
    let log = root.appendingPathComponent("rollout.jsonl")
    let stateURL = dir.appendingPathComponent("state.json")
    try write(fixture("codex.jsonl"), to: log)
    let indexer = LogIndexer(roots: [.codex: root], stateURL: stateURL)
    _ = try await indexer.refresh()
    let duplicate = try fixtureLines("codex.jsonl")[4]
    try append(duplicate + Data([10]), to: log)
    #expect(try await indexer.refresh().buckets.reduce(0) { $0 + $1.totals.total } == 175)
    let next = String(decoding: duplicate, as: UTF8.self).replacingOccurrences(of: "\"total_tokens\":170", with: "\"total_tokens\":220")
    let data = Data(next.utf8)
    try append(Data(data.prefix(50)), to: log)
    #expect(try await indexer.refresh().buckets.reduce(0) { $0 + $1.totals.total } == 175)
    let restored = LogIndexer(roots: [.codex: root], stateURL: stateURL)
    try append(Data(data.dropFirst(50)) + Data([10]), to: log)
    let result = try await restored.refresh()
    #expect(result.buckets.reduce(0) { $0 + $1.totals.total } == 225)
    #expect(result.buckets.first { $0.model == "gpt-test-2" }?.totals.total == 100)
}

@Test func indexerRebuildsOnTruncationAndBadSchema() async throws {
    let dir = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let root = dir.appendingPathComponent("logs")
    let log = root.appendingPathComponent("claude.jsonl")
    let stateURL = dir.appendingPathComponent("state.json")
    try write(fixture("claude.jsonl"), to: log)
    let indexer = LogIndexer(roots: [.claude: root], stateURL: stateURL)
    _ = try await indexer.refresh()
    try write(Data(), to: log)
    #expect(try await indexer.refresh().buckets.isEmpty)
    try write(fixture("claude.jsonl"), to: log)
    try write(Data("{\"schemaVersion\":-1}".utf8), to: stateURL)
    let restored = LogIndexer(roots: [.claude: root], stateURL: stateURL)
    #expect(try await restored.refresh().buckets.reduce(0) { $0 + $1.totals.total } == 100)
    #expect(try await restored.refresh(forceRebuild: true).buckets.reduce(0) { $0 + $1.totals.total } == 100)
    try FileManager.default.removeItem(at: stateURL)
    #expect(try await restored.refresh().bytesRead > 0)
}

@Test func malformedRowsAreCountedAndMissingToolsAreEmpty() async throws {
    let dir = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let root = dir.appendingPathComponent("logs")
    let stateURL = dir.appendingPathComponent("state.json")
    let indexer = LogIndexer(roots: [.claude: root], stateURL: stateURL)
    #expect(try await indexer.refresh().buckets.isEmpty)
    try write(Data("{\"type\":\"assistant\",broken}\n".utf8) + fixture("claude.jsonl"), to: root.appendingPathComponent("log.jsonl"))
    let result = try await indexer.refresh()
    #expect(result.malformedLines == 1)
    #expect(result.buckets.reduce(0) { $0 + $1.totals.total } == 100)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["AIUSAGE_BENCHMARK_STATE"] != nil))
func liveIndexBenchmark() async throws {
    let statePath = try #require(ProcessInfo.processInfo.environment["AIUSAGE_BENCHMARK_STATE"])
    let paths = AppPaths()
    let roots: [Provider: URL] = [.claude: paths.claudeHome.appendingPathComponent("projects"), .codex: paths.codexHome.appendingPathComponent("sessions")]
    let stateURL = URL(fileURLWithPath: statePath)
    let indexer = LogIndexer(roots: roots, stateURL: stateURL)
    let start = Date.now
    let result = try await indexer.refresh(forceRebuild: true)
    print("BENCHMARK cold_seconds=\(Date.now.timeIntervalSince(start)) bytes=\(result.bytesRead) buckets=\(result.buckets.count) malformed=\(result.malformedLines)")
    let warmStart = Date.now
    let warm = try await LogIndexer(roots: roots, stateURL: stateURL).refresh()
    print("BENCHMARK warm_seconds=\(Date.now.timeIntervalSince(warmStart)) bytes=\(warm.bytesRead)")
    #expect(!result.buckets.isEmpty)
    #expect(result.unreadableFiles == 0)
}
