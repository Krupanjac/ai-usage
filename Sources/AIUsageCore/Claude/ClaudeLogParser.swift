import Foundation

public struct ClaudeLogParser: Sendable {
    private let decoder = JSONDecoder()
    public init() {}
    public func parse(_ data: Data) throws -> TokenEvent? {
        let row = try decoder.decode(Row.self, from: data)
        guard row.type == "assistant", let requestID = row.requestId, !requestID.isEmpty,
              let message = row.message, let id = message.id, !id.isEmpty,
              let model = message.model, model != "<synthetic>", let usage = message.usage,
              let timestamp = row.timestamp, let date = TimestampParser.parse(timestamp) else { return nil }
        let totals = TokenTotals(input: usage.input_tokens ?? 0, output: usage.output_tokens ?? 0,
                                 cacheRead: usage.cache_read_input_tokens ?? 0, cacheWrite: usage.cache_creation_input_tokens ?? 0)
        guard totals.total > 0 else { return nil }
        return TokenEvent(provider: .claude, date: date, model: model, totals: totals, deduplicationKey: id + ":" + requestID)
    }
    private struct Row: Decodable {
        var type: String?
        var timestamp: String?
        var requestId: String?
        var message: Message?
    }
    private struct Message: Decodable { var id: String?; var model: String?; var usage: Usage? }
    private struct Usage: Decodable {
        var input_tokens: Int?
        var output_tokens: Int?
        var cache_creation_input_tokens: Int?
        var cache_read_input_tokens: Int?
    }
}
