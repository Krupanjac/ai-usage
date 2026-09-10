import Foundation

public enum Aggregation {
    public static func hour(containing date: Date) -> Date {
        Date(timeIntervalSince1970: floor(date.timeIntervalSince1970 / 3600) * 3600)
    }

    public static func series(buckets: [HourlyBucket], provider: Provider, range: ChartRange,
                              now: Date = .now, calendar: Calendar = .autoupdatingCurrent) -> [DailyUsage] {
        let end = range.isHourly ? hour(containing: now) : calendar.startOfDay(for: now)
        let component: Calendar.Component = range.isHourly ? .hour : .day
        guard let start = calendar.date(byAdding: component, value: -(range.count - 1), to: end) else { return [] }
        var totals: [Date: TokenTotals] = [:]
        for bucket in buckets where bucket.provider == provider && bucket.hour >= start && bucket.hour <= now {
            let date = range.isHourly ? bucket.hour : calendar.startOfDay(for: bucket.hour)
            totals[date, default: TokenTotals()] += bucket.totals
        }
        return (0..<range.count).compactMap { index in
            guard let date = calendar.date(byAdding: component, value: index, to: start) else { return nil }
            return DailyUsage(date: date, totals: totals[date, default: TokenTotals()])
        }
    }
}
