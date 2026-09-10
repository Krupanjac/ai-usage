import Foundation

// Credentials deliberately do not conform to Codable or CustomStringConvertible.
public struct Credential: Sendable {
    public var accessToken: String
    public var accountID: String?
    public var expiresAt: Date?
    public var planType: String?
    public init(accessToken: String, accountID: String? = nil, expiresAt: Date? = nil, planType: String? = nil) {
        self.accessToken = accessToken; self.accountID = accountID; self.expiresAt = expiresAt; self.planType = planType
    }
    public func validated(now: Date = .now) throws -> Self {
        guard !accessToken.isEmpty else { throw CredentialError.missing }
        if let expiresAt, expiresAt <= now { throw CredentialError.expired }
        return self
    }
}

public enum CredentialError: Error, Equatable, Sendable { case missing, expired, malformed, unsupportedAuthMode }
public enum QuotaError: Error, Equatable, Sendable {
    case unauthorized
    case rateLimited(retryAfter: Date?)
    case transport
    case badResponse(statusCode: Int?)
}

public enum ProviderStatus: Equatable, Sendable {
    case loading, available, notInstalled, signIn, expired, offline
    case rateLimited(until: Date)
    case failed
}

public struct ProviderState: Sendable {
    public var provider: Provider
    public var quota: QuotaSnapshot?
    public var status: ProviderStatus = .loading
    public var isRefreshing = false
    public var lastAttempt: Date?
    public init(provider: Provider) { self.provider = provider }
}

public protocol UsageProvider: Sendable {
    var id: Provider { get }
    var homeDir: URL { get }
    var logRoot: URL { get }
    func loadCredential() async throws -> Credential
    func fetchQuota(credential: Credential) async throws -> QuotaSnapshot
    func localQuotaSnapshot() async -> QuotaSnapshot?
}

public extension UsageProvider {
    var isInstalled: Bool { FileManager.default.fileExists(atPath: homeDir.path) }
    func localQuotaSnapshot() async -> QuotaSnapshot? { nil }
}

public struct HTTPResponse: Sendable {
    public var data: Data
    public var statusCode: Int
    public var headers: [String: String]
    public init(data: Data, statusCode: Int, headers: [String: String] = [:]) {
        self.data = data; self.statusCode = statusCode; self.headers = headers
    }
}

public protocol QuotaTransport: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

public struct URLSessionQuotaTransport: QuotaTransport {
    private let session: URLSession
    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        config.urlCache = nil
        config.httpCookieStorage = nil
        session = URLSession(configuration: config)
    }
    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw QuotaError.badResponse(statusCode: nil) }
            var headers: [String: String] = [:]
            for (key, value) in http.allHeaderFields { headers[String(describing: key).lowercased()] = String(describing: value) }
            return HTTPResponse(data: data, statusCode: http.statusCode, headers: headers)
        } catch is CancellationError { throw CancellationError() }
        catch let error as QuotaError { throw error }
        catch { throw QuotaError.transport }
    }
}

public enum QuotaHTTP {
    public static func validate(_ response: HTTPResponse, now: Date = .now) throws {
        switch response.statusCode {
        case 200..<300: return
        case 401, 403: throw QuotaError.unauthorized
        case 429:
            let header = response.headers.first { $0.key.lowercased() == "retry-after" }?.value
            throw QuotaError.rateLimited(retryAfter: retryAfter(header, now: now))
        default: throw QuotaError.badResponse(statusCode: response.statusCode)
        }
    }
    public static func retryAfter(_ value: String?, now: Date = .now) -> Date? {
        guard let value else { return nil }
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let seconds = Double(clean), seconds.isFinite { return now.addingTimeInterval(max(0, seconds)) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        return formatter.date(from: clean).map { max(now, $0) }
    }
}
