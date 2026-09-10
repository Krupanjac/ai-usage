import Foundation

public struct CodexParserState: Codable, Equatable, Sendable {
    public var model: String = "Unknown"
    public var previousTotal: Int?
    public init() {}
}

public struct CodexParseResult: Sendable {
    public var event: TokenEvent?
    public var quota: QuotaSnapshot?
}

public struct CodexLogParser: Sendable {
    private let decoder = JSONDecoder()
    public init() {}
    public func parse(_ data: Data, state: inout CodexParserState) throws -> CodexParseResult {
        let row = try decoder.decode(Row.self, from: data)
        var result = CodexParseResult()
        guard let payload = row.payload else { return result }
        if row.type == "turn_context" {
            if let model = payload.model { state.model = model }
            return result
        }
        guard row.type == "event_msg", payload.type == "token_count",
              let timestamp = row.timestamp, let date = TimestampParser.parse(timestamp) else { return result }
        result.quota = payload.rate_limits?.snapshot(at: date)
        guard let info = payload.info, let total = info.total_token_usage?.total_tokens else { return result }
        let previous = state.previousTotal
        state.previousTotal = total
        guard previous != total, let usage = info.last_token_usage else { return result }
        let cached = max(0, usage.cached_input_tokens ?? 0)
        let totals = TokenTotals(input: max(0, usage.input_tokens ?? 0) - cached, output: usage.output_tokens ?? 0,
                                 cacheRead: cached, cacheWrite: usage.cache_write_input_tokens ?? 0)
        guard totals.total > 0 else { return result }
        result.event = TokenEvent(provider: .codex, date: date, model: state.model, totals: totals)
        return result
    }

    // A bounded startup hint. The indexer subsequently searches every log and picks the newest timestamp.
    public static func newestSnapshot(in root: URL, fileLimit: Int = 5, tailBytes: Int = 512 * 1024) -> QuotaSnapshot? {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return nil }
        var files: [(URL, Date)] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            files.append((url, values.contentModificationDate ?? .distantPast))
        }
        var newest: QuotaSnapshot?
        let parser = CodexLogParser()
        for (url, _) in files.sorted(by: { $0.1 > $1.1 }).prefix(fileLimit) {
            guard let handle = try? FileHandle(forReadingFrom: url) else { continue }
            defer { try? handle.close() }
            guard let size = try? handle.seekToEnd() else { continue }
            let offset = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
            try? handle.seek(toOffset: offset)
            guard let data = try? handle.readToEnd() else { continue }
            var state = CodexParserState()
            var start = data.startIndex
            if offset > 0 { guard let newline = data.firstIndex(of: 10) else { continue }; start = newline + 1 }
            while start < data.endIndex, let newline = data[start...].firstIndex(of: 10) {
                let line = data[start..<newline]
                if line.range(of: Data("\"token_count\"".utf8)) != nil,
                   let result = try? parser.parse(Data(line), state: &state) {
                    newest = QuotaSnapshot.newest([newest, result.quota])
                }
                start = newline + 1
            }
        }
        return newest
    }
    private struct Row: Decodable { var type: String?; var timestamp: String?; var payload: Payload? }
    private struct Payload: Decodable {
        var type: String?
        var model: String?
        var info: Info?
        var rate_limits: RateLimits?
    }
    private struct Info: Decodable { var total_token_usage: Usage?; var last_token_usage: Usage? }
    private struct Usage: Decodable {
        var input_tokens: Int?
        var cached_input_tokens: Int?
        var cache_write_input_tokens: Int?
        var output_tokens: Int?
        var total_tokens: Int?
    }
    private struct RateLimits: Decodable {
        var limit_id: String?
        var primary: Window?
        var secondary: Window?
        var plan_type: String?
        func snapshot(at date: Date) -> QuotaSnapshot? {
            guard limit_id == nil || limit_id == "codex" else { return nil }
            var result = QuotaSnapshot(provider: .codex, planType: plan_type, asOf: date, source: .localLog)
            for value in [primary, secondary].compactMap({ $0 }) {
                guard let percent = value.used_percent, let minutes = value.window_minutes else { continue }
                let window = QuotaWindow(usedPercent: percent, resetsAt: value.resets_at.map { Date(timeIntervalSince1970: $0) },
                                         windowLength: minutes * 60)
                if minutes == 300 { result.fiveHour = window }
                else if minutes == 10080 { result.weekly = window }
            }
            return result.fiveHour == nil && result.weekly == nil ? nil : result
        }
    }
    private struct Window: Decodable { var used_percent: Double?; var window_minutes: Int?; var resets_at: Double? }
}
