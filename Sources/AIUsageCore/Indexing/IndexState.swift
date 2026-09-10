import Foundation

public struct IndexedFile: Codable, Sendable {
    public var offset: UInt64
    public var size: UInt64
    public var modifiedAt: Date
    public var identity: UInt64
    public var parserState: CodexParserState
}

public struct IndexState: Codable, Sendable {
    public static let currentSchemaVersion = 1
    public var schemaVersion = currentSchemaVersion
    public var files: [String: IndexedFile] = [:]
    public var buckets: [String: HourlyBucket] = [:]
    public var seenClaudeKeys: Set<String> = []
    public var newestCodexRateLimits: QuotaSnapshot?
    public var malformedLines = 0
    public var isComplete = false
    public var lastIndexedAt: Date?
    public init() {}
}

public struct IndexProgress: Equatable, Sendable {
    public var completedFiles: Int = 0
    public var totalFiles: Int = 0
    public var bytesRead: UInt64 = 0
    public var totalBytes: UInt64 = 0
    public var isRebuilding = false
    public var isRunning = false
    public var fraction: Double { totalFiles == 0 ? 0 : Double(completedFiles) / Double(totalFiles) }
    public init() {}
}

public struct IndexResult: Sendable {
    public var buckets: [HourlyBucket]
    public var localQuota: QuotaSnapshot?
    public var malformedLines: Int
    public var unreadableFiles: Int
    public var bytesRead: UInt64
    public var indexedAt: Date?
}
