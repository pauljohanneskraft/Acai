import Foundation

/// A repository owner's login. Kept as a sibling of `GitHubAPIClient.Repository` rather than nested,
/// so no declared type here nests more than one level deep.
struct GitHubRepositoryOwner: Decodable, Hashable {
    var login: String
}

/// A branch or tag name. `kind` is attached after decoding (the endpoints don't return it) and
/// folded into `id` so a branch and tag sharing a name don't collide as `Identifiable` ids when
/// both lists are combined into one `ForEach`/`Picker`.
struct GitHubRef: Identifiable, Hashable {
    enum Kind: String, Hashable, Codable {
        case branch
        case tag
    }

    var name: String
    var kind: Kind
    var id: String { "\(kind.rawValue)-\(name)" }
}

/// The bare shape the branches/tags endpoints actually return.
private struct GitHubRefResponse: Decodable {
    var name: String
}

/// An open pull request, for the Compare panel's PR picker.
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

/// The bare shape `GET repos/{owner}/{repo}/pulls` actually returns.
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
                "GitHub API error \(status): \(message)"
            case .decoding(let message):
                "Couldn't parse GitHub's response: \(message)"
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

    /// `authenticatedUserWithMetadata()`'s result: the signed-in user plus what GitHub's response
    /// headers reveal about the token itself (the scope checklist, the expiry prompt).
    struct AuthenticatedUserInfo: Sendable {
        var user: User
        /// Parsed from the `X-OAuth-Scopes` response header (comma-separated) — sent for classic
        /// PATs and OAuth/device-flow tokens. `nil` when the header is absent (fine-grained PATs
        /// don't currently send it), meaning "unknown," not "confirmed to have no scopes."
        var scopes: [String]?
        /// Parsed from the `github-authentication-token-expiration` response header, when GitHub
        /// sends it (fine-grained PATs report this; classic tokens generally don't).
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

    /// `GET /user` — the signed-in account's login/avatar, for display.
    func authenticatedUser() async throws -> User {
        try await get("user", as: User.self)
    }

    /// `GET /user`, plus what the response headers reveal about the token itself — the scope
    /// checklist and expiry prompt both read this instead of the plain `authenticatedUser()`
    /// above (kept as-is since nothing else needs the metadata).
    func authenticatedUserWithMetadata() async throws -> AuthenticatedUserInfo {
        let (user, response) = try await getWithResponse("user", as: User.self)
        return AuthenticatedUserInfo(
            user: user,
            scopes: response?.gitHubOAuthScopes,
            tokenExpiresAt: response?.gitHubTokenExpiresAt
        )
    }

    /// Page size for `repositories(page:)` — a response shorter than this is the last page.
    static let repositoriesPerPage = 50

    /// `GET /user/repos` — one page; the picker does client-side substring filtering over fetched
    /// pages. Callers wanting every repository should page until a shorter response comes back.
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

    /// `GET /repos/{owner}/{repo}/branches` — for the ref picker.
    func branches(owner: String, repo: String) async throws -> [GitHubRef] {
        try await get(
            "repos/\(owner)/\(repo)/branches",
            query: [URLQueryItem(name: "per_page", value: "100")],
            as: [GitHubRefResponse].self
        ).map { GitHubRef(name: $0.name, kind: .branch) }
    }

    /// `GET /repos/{owner}/{repo}/tags` — for the ref picker.
    func tags(owner: String, repo: String) async throws -> [GitHubRef] {
        try await get(
            "repos/\(owner)/\(repo)/tags",
            query: [URLQueryItem(name: "per_page", value: "100")],
            as: [GitHubRefResponse].self
        ).map { GitHubRef(name: $0.name, kind: .tag) }
    }

    /// `GET /repos/{owner}/{repo}/pulls` — open pull requests, for the Compare panel's PR picker.
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
    /// `X-OAuth-Scopes` is a comma-separated list GitHub sends for classic PATs and OAuth/device-flow
    /// tokens; fine-grained PATs don't currently send it — absence means "unknown," not "none."
    var gitHubOAuthScopes: [String]? {
        guard let raw = value(forHTTPHeaderField: "X-OAuth-Scopes"), !raw.isEmpty else { return nil }
        return raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// `github-authentication-token-expiration`, when GitHub sends it (fine-grained PATs report
    /// this). Parsed leniently (ISO 8601, falling back to an RFC-1123-ish format) — an unrecognized
    /// format degrades to `nil` ("no known expiry"), never a crash on an unexpected header value.
    var gitHubTokenExpiresAt: Date? {
        guard let raw = value(forHTTPHeaderField: "github-authentication-token-expiration") else { return nil }
        if let date = ISO8601DateFormatter().date(from: raw) { return date }
        let rfc1123 = DateFormatter()
        rfc1123.locale = Locale(identifier: "en_US_POSIX")
        rfc1123.dateFormat = "yyyy-MM-dd HH:mm:ss zzz"
        return rfc1123.date(from: raw)
    }
}
