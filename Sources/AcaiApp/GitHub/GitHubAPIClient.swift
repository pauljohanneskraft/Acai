import Foundation

struct GitHubRepositoryOwner: Decodable, Hashable {
    var login: String
}

/// `kind` is folded into `id` so a branch and tag sharing a name don't collide as `Identifiable`
/// ids when both lists are combined into one `ForEach`/`Picker`.
struct GitHubRef: Identifiable, Hashable {
    enum Kind: String, Hashable, Codable {
        case branch
        case tag
    }

    var name: String
    var kind: Kind
    var id: String { "\(kind.rawValue)-\(name)" }
}

private struct GitHubRefResponse: Decodable {
    var name: String
}

struct GitHubPullRequest: Identifiable, Hashable {
    var number: Int
    var title: String
    var authorLogin: String
    /// The branch the PR targets (the "old" side of a three-dot comparison, via its merge-base
    /// with `headRef`).
    var baseRef: String
    /// The branch/SHA carrying the PR's own commits (the "new" side).
    var headRef: String
    var state: String

    var id: Int { number }
}

private struct GitHubPullRequestResponse: Decodable {
    struct Branch: Decodable {
        var ref: String
    }

    var number: Int
    var title: String
    var user: GitHubRepositoryOwner
    var base: Branch
    var head: Branch
    var state: String
}

/// A thin, read-only `URLSession`-based client for the GitHub REST API — every endpoint here is a
/// `GET`, and none of them can mutate anything on GitHub regardless of what the credential allows.
struct GitHubAPIClient {
    var credential: GitHubCredential
    var session: URLSession = .shared

    private var baseURL: URL { URL(string: "https://api.github.com")! }

    enum Failure: LocalizedError {
        case http(Int, String)
        case decoding(String)

        var errorDescription: String? {
            switch self {
            case .http(let status, let message):
                String(localized: .app("Error.GitHubAPIClient.Http \(status) \(message)"))
            case .decoding(let message):
                String(localized: .app("Error.GitHubAPIClient.Decoding \(message)"))
            }
        }
    }

    struct User: Decodable {
        var login: String
        var avatarURL: URL?

        enum CodingKeys: String, CodingKey {
            case login
            case avatarURL = "avatar_url"
        }
    }

    struct AuthenticatedUserInfo: Sendable {
        var user: User
        var scopes: [String]?
        var tokenExpiresAt: Date?
    }

    struct Repository: Decodable, Identifiable, Hashable {
        var id: Int
        var name: String
        var fullName: String
        var owner: GitHubRepositoryOwner
        var defaultBranch: String
        var isPrivate: Bool

        enum CodingKeys: String, CodingKey {
            case id, name, owner
            case fullName = "full_name"
            case defaultBranch = "default_branch"
            case isPrivate = "private"
        }
    }

    func authenticatedUser() async throws -> User {
        try await get("user", as: User.self)
    }

    /// Same endpoint as `authenticatedUser()`, plus what the response headers reveal about the
    /// token itself — the scope checklist and expiry prompt both read this instead.
    func authenticatedUserWithMetadata() async throws -> AuthenticatedUserInfo {
        let (user, response) = try await getWithResponse("user", as: User.self)
        return AuthenticatedUserInfo(
            user: user,
            scopes: response?.gitHubOAuthScopes,
            tokenExpiresAt: response?.gitHubTokenExpiresAt
        )
    }

    /// A response shorter than this is the last page.
    static let repositoriesPerPage = 50

    func repositories(page: Int = 1) async throws -> [Repository] {
        try await get(
            "user/repos",
            query: [
                URLQueryItem(name: "per_page", value: String(Self.repositoriesPerPage)),
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "sort", value: "updated")
            ],
            as: [Repository].self
        )
    }

    func branches(owner: String, repo: String) async throws -> [GitHubRef] {
        try await get(
            "repos/\(owner)/\(repo)/branches",
            query: [URLQueryItem(name: "per_page", value: "100")],
            as: [GitHubRefResponse].self
        ).map { GitHubRef(name: $0.name, kind: .branch) }
    }

    func tags(owner: String, repo: String) async throws -> [GitHubRef] {
        try await get(
            "repos/\(owner)/\(repo)/tags",
            query: [URLQueryItem(name: "per_page", value: "100")],
            as: [GitHubRefResponse].self
        ).map { GitHubRef(name: $0.name, kind: .tag) }
    }

    func pullRequests(owner: String, repo: String) async throws -> [GitHubPullRequest] {
        try await get(
            "repos/\(owner)/\(repo)/pulls",
            query: [URLQueryItem(name: "per_page", value: "100")],
            as: [GitHubPullRequestResponse].self
        ).map {
            GitHubPullRequest(
                number: $0.number, title: $0.title, authorLogin: $0.user.login,
                baseRef: $0.base.ref, headRef: $0.head.ref, state: $0.state)
        }
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [], as type: T.Type) async throws -> T {
        try await getWithResponse(path, query: query, as: type).0
    }

    private func getWithResponse<T: Decodable>(
        _ path: String, query: [URLQueryItem] = [], as type: T.Type
    ) async throws -> (T, HTTPURLResponse?) {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.setValue(credential.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
        do {
            return (try JSONDecoder().decode(T.self, from: data), response as? HTTPURLResponse)
        } catch {
            throw Failure.decoding(error.localizedDescription)
        }
    }

    private func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw Failure.http(http.statusCode, message)
        }
    }
}

extension HTTPURLResponse {
    var gitHubOAuthScopes: [String]? {
        guard let raw = value(forHTTPHeaderField: "X-OAuth-Scopes"), !raw.isEmpty else { return nil }
        return raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Parsed leniently (ISO 8601, falling back to an RFC-1123-ish format) — an unrecognized
    /// format degrades to `nil` rather than crashing.
    var gitHubTokenExpiresAt: Date? {
        guard let raw = value(forHTTPHeaderField: "github-authentication-token-expiration") else { return nil }
        if let date = ISO8601DateFormatter().date(from: raw) { return date }
        let rfc1123 = DateFormatter()
        rfc1123.locale = Locale(identifier: "en_US_POSIX")
        rfc1123.dateFormat = "yyyy-MM-dd HH:mm:ss zzz"
        return rfc1123.date(from: raw)
    }
}
