import Foundation

/// A repository owner's login, as GitHub's API nests it under `Repository.owner`. Kept as a
/// sibling of `GitHubAPIClient.Repository` rather than nested inside it, so no declared type here
/// nests more than one level deep.
struct GitHubRepositoryOwner: Decodable, Hashable {
    var login: String
}

/// A branch or tag name, as returned by the branches/tags list endpoints.
struct GitHubRef: Decodable, Identifiable, Hashable {
    var name: String
    var id: String { name }
}

/// The head-commit response shape from `GET /repos/{owner}/{repo}/commits/{ref}` — only the field
/// `GitHubAPIClient.headCommitSHA` needs.
private struct GitHubCommitResponse: Decodable {
    var sha: String
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

    /// `GET /user/repos` — paginated; the picker does client-side substring filtering over
    /// fetched pages, which is enough for typical account sizes.
    func repositories(page: Int = 1) async throws -> [Repository] {
        try await get(
            "user/repos",
            query: [
                URLQueryItem(name: "per_page", value: "50"),
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
            as: [GitHubRef].self
        )
    }

    /// `GET /repos/{owner}/{repo}/tags` — for the ref picker.
    func tags(owner: String, repo: String) async throws -> [GitHubRef] {
        try await get(
            "repos/\(owner)/\(repo)/tags",
            query: [URLQueryItem(name: "per_page", value: "100")],
            as: [GitHubRef].self
        )
    }

    /// The head commit SHA for `ref` (a branch, tag, or SHA) — used to decide whether a pull
    /// needs to re-download anything.
    func headCommitSHA(owner: String, repo: String, ref: String) async throws -> String {
        try await get("repos/\(owner)/\(repo)/commits/\(ref)", as: GitHubCommitResponse.self).sha
    }

    /// The zip GitHub builds server-side for `ref` — `GitHubRepositoryClone` extracts this.
    /// Follows the redirect to `codeload.github.com` via the default `URLSession` behavior.
    func zipballData(owner: String, repo: String, ref: String) async throws -> Data {
        let url = baseURL.appendingPathComponent("repos/\(owner)/\(repo)/zipball/\(ref)")
        var request = URLRequest(url: url)
        request.setValue(credential.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
        return data
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
