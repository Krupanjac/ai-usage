import Foundation

public enum TimestampParser {
    private static let fallback = ISO8601Fallback()

    public static func parse(_ string: String) -> Date? {
        // Most transcript timestamps take this allocation-free Gregorian UTC path.
        if let fast = string.utf8.withContiguousStorageIfAvailable({ bytes -> Date? in
            guard bytes.count == 24, bytes[4] == 45, bytes[7] == 45, bytes[10] == 84,
                  bytes[13] == 58, bytes[16] == 58, bytes[19] == 46, bytes[23] == 90 else { return nil }
            func number(_ start: Int, _ count: Int) -> Int {
                var result = 0
                for i in start..<(start + count) {
                    guard bytes[i] >= 48, bytes[i] <= 57 else { return -1 }
                    result = result * 10 + Int(bytes[i] - 48)
                }
                return result
            }
            let year = number(0, 4), month = number(5, 2), day = number(8, 2)
            let hour = number(11, 2), minute = number(14, 2), second = number(17, 2), ms = number(20, 3)
            guard year >= 1, (1...12).contains(month), (0...23).contains(hour),
                  (0...59).contains(minute), (0...59).contains(second), ms >= 0 else { return nil }
            let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
            let daysInMonth = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
            guard (1...daysInMonth[month - 1]).contains(day) else { return nil }
            let y = year - (month <= 2 ? 1 : 0)
            let era = y / 400, yoe = y - (y / 400) * 400
            let shiftedMonth = month + (month > 2 ? -3 : 9)
            let doy = (153 * shiftedMonth + 2) / 5 + day - 1
            let days = era * 146097 + yoe * 365 + yoe / 4 - yoe / 100 + doy - 719468
            return Date(timeIntervalSince1970: Double(days * 86400 + hour * 3600 + minute * 60 + second) + Double(ms) / 1000)
        }) ?? nil { return fast }
        return fallback.parse(string)
    }
}

private final class ISO8601Fallback: @unchecked Sendable {
    private let lock = NSLock()
    private let fractional: ISO8601DateFormatter
    private let whole = ISO8601DateFormatter()
    init() {
        fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }
    func parse(_ string: String) -> Date? {
        lock.lock(); defer { lock.unlock() }
        return fractional.date(from: string) ?? whole.date(from: string)
    }
}
