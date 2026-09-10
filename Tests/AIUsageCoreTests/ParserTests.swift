import Foundation
import Testing
@testable import AIUsageCore

@Test func claudeStreamingRowsHaveStableKeysAndSkipNonUsage() throws {
    let parser = ClaudeLogParser()
    let events = try fixtureLines("claude.jsonl").compactMap { try parser.parse($0) }
    #expect(events.count == 3)
    #expect(Set(events.compactMap(\.deduplicationKey)).count == 1)
    #expect(events.first?.totals == TokenTotals(input: 10, output: 20, cacheRead: 40, cacheWrite: 30))
    #expect(events.first?.date == TimestampParser.parse("2026-09-09T23:15:00.000Z"))
}

@Test func codexUsageIsNormalizedAndDuplicateTotalsStillUpdateQuota() throws {
    let parser = CodexLogParser()
    var state = CodexParserState()
    let results = try fixtureLines("codex.jsonl").map { try parser.parse($0, state: &state) }
    let events = results.compactMap(\.event)
    #expect(events.count == 2)
    #expect(events.map(\.model) == ["gpt-test-1", "gpt-test-2"])
    #expect(events[0].totals == TokenTotals(input: 60, output: 20, cacheRead: 40, cacheWrite: 5))
    #expect(events[1].totals == TokenTotals(input: 30, output: 10, cacheRead: 10))
    #expect(results[2].event == nil)
    #expect(results[2].quota?.weekly?.usedPercent == 28)
    #expect(results[4].quota?.fiveHour?.usedPercent == 12)
    #expect(results[4].quota?.weekly?.usedPercent == 29)
    #expect(results[5].quota == nil)
    #expect(state.previousTotal == 170)
}

@Test func codexTotalsArePerFileAndResetsDoNotLoseResponses() throws {
    let row = try fixtureLines("codex.jsonl")[1]
    let parser = CodexLogParser()
    var state = CodexParserState()
    state.previousTotal = 500
    #expect(try parser.parse(row, state: &state).event != nil)
    #expect(try parser.parse(row, state: &state).event == nil)
    var anotherFile = CodexParserState()
    #expect(try parser.parse(row, state: &anotherFile).event != nil)
}

@Test func tailSnapshotIgnoresIncompleteAndNullRows() throws {
    let dir = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("session.jsonl")
    try write(fixture("codex.jsonl"), to: url)
    let newest = CodexLogParser.newestSnapshot(in: dir)
    #expect(newest?.weekly?.usedPercent == 29)
    #expect(newest?.source == .localLog)
    try append(Data("{\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\"".utf8), to: url)
    #expect(CodexLogParser.newestSnapshot(in: dir) == newest)
}

@Test func timestampsSupportTranscriptAndEndpointFormats() throws {
    #expect(TimestampParser.parse("1970-01-01T00:00:00.000Z") == Date(timeIntervalSince1970: 0))
    #expect(TimestampParser.parse("2024-02-29T23:00:01.123Z")?.timeIntervalSince1970 == 1709247601.123)
    let microseconds = try #require(TimestampParser.parse("2026-09-10T17:00:00.528743+00:00"))
    let milliseconds = try #require(TimestampParser.parse("2026-09-10T17:00:00.528Z"))
    #expect(abs(microseconds.timeIntervalSince(milliseconds)) < 0.001)
    #expect(TimestampParser.parse("2026-09-10T19:00:00+02:00") == TimestampParser.parse("2026-09-10T17:00:00.000Z"))
    #expect(TimestampParser.parse("not a date") == nil)
}
