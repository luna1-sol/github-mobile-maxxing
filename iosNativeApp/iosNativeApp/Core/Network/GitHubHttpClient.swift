import Foundation
import Observation

struct GitHubAPIError: LocalizedError, Equatable {
    var statusCode: Int
    var message: String
    /// True for statuses the client picked itself (e.g. a GraphQL error delivered with HTTP 200).
    var isSynthetic = false

    var errorDescription: String? { message }
}

/// Thin HTTP layer over `URLSession` for api.github.com (port of `GitHubNetworkConfig`):
/// default headers, bearer token with refresh-before-expiry and retry-after-401, rate limit tracking,
/// and a redirect guard that never forwards the token to another host.
@Observable
final class GitHubHttpClient {
    let baseURL: URL
    private(set) var rateLimit = RateLimitInfo()

    @ObservationIgnored private let sessionManager: SessionManager
    @ObservationIgnored private let urlSession: URLSession

    init(sessionManager: SessionManager, baseURL: URL = URL(string: "https://api.github.com")!) {
        self.sessionManager = sessionManager
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.requestCachePolicy = .useProtocolCachePolicy
        config.urlCache = URLCache(memoryCapacity: 16 << 20, diskCapacity: 64 << 20)
        urlSession = URLSession(configuration: config)
    }

    enum Method: String { case get = "GET", post = "POST", put = "PUT", patch = "PATCH", delete = "DELETE" }

    /// Sends a request to `path` (already percent-encoded, relative to `baseURL`).
    @discardableResult
    func send(
        _ method: Method = .get,
        _ path: String,
        query: [String: String] = [:],
        body: JSONValue? = nil,
        accept: String = "application/vnd.github+json",
        noCache: Bool = false
    ) async throws -> (Data, HTTPURLResponse) {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        components.percentEncodedPath = (components.percentEncodedPath.hasSuffix("/") ? String(components.percentEncodedPath.dropLast()) : components.percentEncodedPath)
            + (path.hasPrefix("/") ? path : "/" + path)
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue(AppBranding.userAgent, forHTTPHeaderField: "User-Agent")
        if noCache {
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        }
        if let body {
            request.httpBody = try body.encoded()
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let token = await sessionManager.validAccessToken()
        var (data, response) = try await perform(request, token: token)
        if response.statusCode == 401, let token,
           let newToken = await sessionManager.tokenAfterUnauthorized(token) {
            (data, response) = try await perform(request, token: newToken)
        }
        return (data, response)
    }

    /// Sends a request and decodes the body as JSON, throwing `GitHubAPIError` for non-2xx statuses.
    func json(
        _ method: Method = .get,
        _ path: String,
        query: [String: String] = [:],
        body: JSONValue? = nil,
        noCache: Bool = false,
        failure: @autoclosure () -> String
    ) async throws -> JSONValue {
        let (data, response) = try await send(method, path, query: query, body: body, noCache: noCache)
        try Self.ensureSuccess(response, data: data, failure: failure())
        if data.isEmpty || response.statusCode == 204 { return .null }
        return try JSONValue.parse(data)
    }

    /// Sends a request whose response body is not needed.
    func expectSuccess(
        _ method: Method,
        _ path: String,
        body: JSONValue? = nil,
        failure: @autoclosure () -> String
    ) async throws {
        let (data, response) = try await send(method, path, body: body)
        try Self.ensureSuccess(response, data: data, failure: failure())
    }

    func graphQL(_ query: String, variables: [String: JSONValue] = [:]) async throws -> JSONValue {
        let (data, response) = try await send(.post, "graphql", body: ["query": .string(query), "variables": .object(variables)])
        guard (200..<300).contains(response.statusCode) else {
            throw GitHubAPIError(statusCode: response.statusCode, message: "GraphQL HTTP \(response.statusCode)")
        }
        let body = try JSONValue.parse(data)
        let errors = body["errors"]?.items ?? []
        guard let payload = body["data"] else {
            if !errors.isEmpty {
                let message = errors.compactMap { $0["message"]?.string }.joined(separator: "; ")
                throw GitHubAPIError(statusCode: 422, message: message, isSynthetic: true)
            }
            throw GitHubAPIError(statusCode: 500, message: "Empty GraphQL response", isSynthetic: true)
        }
        return payload
    }

    static func ensureSuccess(_ response: HTTPURLResponse, data: Data, failure: String) throws {
        guard !(200..<300).contains(response.statusCode) else { return }
        // Prefer GitHub's own message ("Pull Request is not mergeable", "Validation Failed", ...).
        let apiMessage = (try? JSONValue.parse(data))?["message"]?.string
        let message = apiMessage.map { "\(failure): \($0) (\(response.statusCode))" } ?? "\(failure) (\(response.statusCode))"
        throw GitHubAPIError(statusCode: response.statusCode, message: message)
    }

    private func perform(_ original: URLRequest, token: String?) async throws -> (Data, HTTPURLResponse) {
        var request = original
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await urlSession.data(for: request, delegate: RedirectGuard.shared)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if let limit = http.value(forHTTPHeaderField: "X-RateLimit-Limit").flatMap(Int.init),
           let remaining = http.value(forHTTPHeaderField: "X-RateLimit-Remaining").flatMap(Int.init) {
            let reset = http.value(forHTTPHeaderField: "X-RateLimit-Reset").flatMap(Int64.init) ?? 0
            rateLimit = RateLimitInfo(limit: limit, remaining: remaining, resetEpochSeconds: reset)
        }
        return (data, http)
    }
}

/// Drops the Authorization header when GitHub redirects to another host (e.g. log or archive downloads).
nonisolated final class RedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    static let shared = RedirectGuard()

    // Completion-handler form on purpose: the async form of this Objective-C delegate method crashes
    // the Swift 6.4 compiler (SILGen native-to-foreign thunk) under NonisolatedNonsendingByDefault.
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        var next = request
        let originalHost = task.originalRequest?.url?.host?.lowercased()
        if next.url?.host?.lowercased() != originalHost {
            next.setValue(nil, forHTTPHeaderField: "Authorization")
        }
        completionHandler(next)
    }
}

// MARK: - Path helpers

enum APIPath {
    private static let segmentAllowed: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.remove(charactersIn: "/?#;")
        return set
    }()

    /// Percent-encodes one path segment (owner, repo, branch name, login...).
    static func seg(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: segmentAllowed) ?? value
    }

    /// Percent-encodes a slash-separated repository sub path segment by segment.
    static func subPath(_ path: String) -> String {
        path.split(separator: "/", omittingEmptySubsequences: true).map { seg(String($0)) }.joined(separator: "/")
    }

    static func repo(_ owner: String, _ name: String) -> String {
        "repos/\(seg(owner))/\(seg(name))"
    }
}
