import Foundation

public enum Provider: String, Codable, CaseIterable, Identifiable, Sendable {
    case claude, codex
    public var id: String { rawValue }
    public var name: String { self == .claude ? "Claude Code" : "Codex" }
    public var command: String { self == .claude ? "claude" : "codex" }
}

public struct QuotaWindow: Codable, Equatable, Sendable {
    public var usedPercent: Double
    public var resetsAt: Date?
    public var windowLength: Int

    public init(usedPercent: Double, resetsAt: Date? = nil, windowLength: Int) {
        self.usedPercent = usedPercent.isFinite ? max(0, usedPercent) : 0
        self.resetsAt = resetsAt
        self.windowLength = windowLength
    }
}

public struct ExtraQuotaWindow: Codable, Equatable, Identifiable, Sendable {
    public var name: String
    public var window: QuotaWindow
    public var id: String { name }
    public init(name: String, window: QuotaWindow) { self.name = name; self.window = window }
}

public struct QuotaSnapshot: Codable, Equatable, Sendable {
    public enum Source: String, Codable, Sendable { case network, localLog, diskCache }
    public var provider: Provider
    public var fiveHour: QuotaWindow?
    public var weekly: QuotaWindow?
    public var extra: [ExtraQuotaWindow]
    public var planType: String?
    public var asOf: Date
    public var source: Source

    public init(provider: Provider, fiveHour: QuotaWindow? = nil, weekly: QuotaWindow? = nil,
                extra: [ExtraQuotaWindow] = [], planType: String? = nil, asOf: Date, source: Source) {
        self.provider = provider; self.fiveHour = fiveHour; self.weekly = weekly
        self.extra = extra; self.planType = planType; self.asOf = asOf; self.source = source
    }

    public var maximumPercent: Double? { [fiveHour?.usedPercent, weekly?.usedPercent].compactMap { $0 }.max() }

    public static func newest(_ candidates: [QuotaSnapshot?]) -> QuotaSnapshot? {
        candidates.compactMap { $0 }.max {
            if $0.asOf == $1.asOf { return $0.source.priority < $1.source.priority }
            return $0.asOf < $1.asOf
        }
    }
}

private extension QuotaSnapshot.Source {
    var priority: Int { switch self { case .network: 2; case .localLog: 1; case .diskCache: 0 } }
}

public enum TokenKind: String, CaseIterable, Identifiable, Sendable {
    case input = "Input", cacheRead = "Cache read", cacheWrite = "Cache write", output = "Output"
    public var id: String { rawValue }
}

public struct TokenTotals: Codable, Equatable, Sendable {
    public var input: Int
    public var output: Int
    public var cacheRead: Int
    public var cacheWrite: Int
    public init(input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheWrite: Int = 0) {
        self.input = max(0, input); self.output = max(0, output)
        self.cacheRead = max(0, cacheRead); self.cacheWrite = max(0, cacheWrite)
    }
    public var total: Int { input + output + cacheRead + cacheWrite }
    public subscript(kind: TokenKind) -> Int {
        switch kind { case .input: input; case .output: output; case .cacheRead: cacheRead; case .cacheWrite: cacheWrite }
    }
    public static func + (lhs: Self, rhs: Self) -> Self {
        Self(input: lhs.input + rhs.input, output: lhs.output + rhs.output,
             cacheRead: lhs.cacheRead + rhs.cacheRead, cacheWrite: lhs.cacheWrite + rhs.cacheWrite)
    }
    public static func += (lhs: inout Self, rhs: Self) { lhs = lhs + rhs }
}

public struct TokenEvent: Equatable, Sendable {
    public var provider: Provider
    public var date: Date
    public var model: String
    public var totals: TokenTotals
    public var deduplicationKey: String?
}

public struct HourlyBucket: Codable, Equatable, Sendable {
    public var hour: Date
    public var provider: Provider
    public var model: String
    public var totals: TokenTotals
    public init(hour: Date, provider: Provider, model: String, totals: TokenTotals) {
        self.hour = hour; self.provider = provider; self.model = model; self.totals = totals
    }
}

public struct DailyUsage: Identifiable, Equatable, Sendable {
    public var date: Date
    public var totals: TokenTotals
    public var id: Date { date }
}

public enum ChartRange: String, CaseIterable, Identifiable, Sendable {
    case day = "24h", fortnight = "14d", month = "30d"
    public var id: String { rawValue }
    public var count: Int { switch self { case .day: 24; case .fortnight: 14; case .month: 30 } }
    public var isHourly: Bool { self == .day }
}
