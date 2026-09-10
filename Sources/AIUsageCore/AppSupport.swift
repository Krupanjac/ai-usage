import Foundation
import OSLog

public struct AppPaths: Sendable {
    public var claudeHome: URL
    public var codexHome: URL
    public var support: URL
    public var indexState: URL { support.appendingPathComponent("index-state.json") }
    public var quotaCache: URL { support.appendingPathComponent("quota-cache.json") }
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                environment: [String: String] = ProcessInfo.processInfo.environment, support: URL? = nil) {
        claudeHome = home.appendingPathComponent(".claude", isDirectory: true)
        if let override = environment["CODEX_HOME"], !override.isEmpty {
            codexHome = URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        } else { codexHome = home.appendingPathComponent(".codex", isDirectory: true) }
        self.support = support ?? home.appendingPathComponent("Library/Application Support/AIUsage", isDirectory: true)
    }
}

public enum AppSupport {
    public static let logger = Logger(subsystem: "dev.krupanjac.AIUsage", category: "usage")
    public static func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        try autoreleasepool { try JSONDecoder().decode(type, from: Data(contentsOf: url)) }
    }
    public static func write<T: Encodable>(_ value: T, to url: URL) throws {
        try autoreleasepool {
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let data = try JSONEncoder().encode(value)
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }
}

public struct QuotaCache: Codable, Sendable {
    public var schemaVersion = 1
    public var snapshots: [Provider: QuotaSnapshot] = [:]
    public var policies: [Provider: RefreshPolicy] = [:]
    public init() {}
}

public actor QuotaCacheStore {
    private let url: URL
    public init(url: URL) { self.url = url }
    public func load() -> QuotaCache {
        guard var cache = try? AppSupport.read(QuotaCache.self, from: url), cache.schemaVersion == 1 else { return QuotaCache() }
        for key in cache.snapshots.keys { cache.snapshots[key]?.source = .diskCache }
        return cache
    }
    public func save(_ cache: QuotaCache) throws { try AppSupport.write(cache, to: url) }
}
