import Foundation
import Testing
@testable import AIUsageCore

@Test func dailyAggregationFollowsLocalDayBoundaries() throws {
    let now = try #require(TimestampParser.parse("2026-09-10T12:00:00.000Z"))
    let hour = try #require(TimestampParser.parse("2026-09-09T23:00:00.000Z"))
    let buckets = [HourlyBucket(hour: hour, provider: .claude, model: "test", totals: TokenTotals(input: 100)),
                   HourlyBucket(hour: hour, provider: .codex, model: "test", totals: TokenTotals(input: 999))]
    var local = Calendar(identifier: .gregorian)
    local.timeZone = try #require(TimeZone(identifier: "Europe/Belgrade"))
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = try #require(TimeZone(secondsFromGMT: 0))
    let localSeries = Aggregation.series(buckets: buckets, provider: .claude, range: .fortnight, now: now, calendar: local)
    let utcSeries = Aggregation.series(buckets: buckets, provider: .claude, range: .fortnight, now: now, calendar: utc)
    #expect(localSeries.count == 14)
    #expect(localSeries.last?.totals.input == 100)
    #expect(utcSeries.last?.totals.total == 0)
    #expect(utcSeries[12].totals.input == 100)
    #expect(localSeries.filter { $0.totals.total == 0 }.count == 13)
}

@Test func hourlyRangeHas24PointsAcrossDaylightSavingChange() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Europe/Belgrade"))
    let now = try #require(TimestampParser.parse("2026-10-25T14:00:00.000Z"))
    let result = Aggregation.series(buckets: [], provider: .codex, range: .day, now: now, calendar: calendar)
    #expect(result.count == 24)
    #expect(Set(result.map(\.date)).count == 24)
    #expect(result.last!.date.timeIntervalSince(result.first!.date) == 23 * 3600)
    #expect(result.allSatisfy { $0.totals.total == 0 })
}
