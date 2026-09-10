import Foundation

public struct RefreshPolicy: Codable, Equatable, Sendable {
    public private(set) var lastAttempt: Date?
    public private(set) var nextAutomaticAttempt = Date.distantPast
    public private(set) var rateLimitUntil: Date?
    public private(set) var rateLimitFailures = 0
    public private(set) var offlineFailures = 0
    public init() {}

    public func canAttempt(now: Date, manual: Bool = false) -> Bool {
        if let rateLimitUntil, now < rateLimitUntil { return false }
        if let lastAttempt, now.timeIntervalSince(lastAttempt) < 60 { return false }
        return manual || now >= nextAutomaticAttempt
    }
    public mutating func beganAttempt(at now: Date) {
        lastAttempt = now
        nextAutomaticAttempt = now.addingTimeInterval(300)
    }
    public mutating func succeeded(at now: Date) {
        rateLimitFailures = 0; offlineFailures = 0; rateLimitUntil = nil
        nextAutomaticAttempt = now.addingTimeInterval(300)
    }
    public mutating func failed(_ error: QuotaError, at now: Date, jitter: Double = Double.random(in: 0.9...1.1)) {
        let jitter = min(1.1, max(0.9, jitter))
        switch error {
        case .rateLimited(let retryAfter):
            rateLimitFailures += 1
            let base = min(3600, 300 * pow(2, Double(min(rateLimitFailures - 1, 4))))
            let delay = min(3600, max(300, base * jitter))
            let until = max(now.addingTimeInterval(delay), retryAfter ?? now)
            rateLimitUntil = until; nextAutomaticAttempt = until
        case .transport, .badResponse:
            offlineFailures += 1
            let delay = min(900, max(300, 300 * pow(2, Double(min(offlineFailures - 1, 2))) * jitter))
            nextAutomaticAttempt = now.addingTimeInterval(delay)
        case .unauthorized:
            nextAutomaticAttempt = now.addingTimeInterval(300)
        }
    }
}
