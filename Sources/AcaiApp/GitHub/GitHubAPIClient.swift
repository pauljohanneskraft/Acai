import Foundation

/// A repository owner's login, as GitHub's API nests it under `Repository.owner`. Kept as a
/// sibling of `GitHubAPIClient.Repository` rather than nested inside it, so no declared type here
/// nests more than one level deep.
struct GitHubRepositoryOwner: Decodable, Hashable {
    var login: String
}

/// A branch or tag name, as returned by the branches/tags list endpoints. `kind` is attached by
/// `GitHubAPIClient.branches`/`.tags` after decoding (the underlying endpoints don't return it) and
/// folded into `id` so a branch and a tag sharing a name (e.g. both called `v1`) don't collide as
/// `Identifiable` ids when the two lists are combined into one `ForEach`/`Picker`.
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

    /// Page size `repositories(page:)` requests — a caller paging through results knows it has
    /// reached the last page once a response comes back shorter than this.
    static let repositoriesPerPage = 50

    /// `GET /user/repos` — one page; the picker does client-side substring filtering over
    /// fetched pages, which is enough for typical account sizes. Callers wanting every repository
    /// should page through until a response shorter than `repositoriesPerPage` comes back.
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

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [], as type: T.Type) async throws -> T {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.setValue(credential.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
        do {
            return try JSONDecoder().decode(T.self, from: data)
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
