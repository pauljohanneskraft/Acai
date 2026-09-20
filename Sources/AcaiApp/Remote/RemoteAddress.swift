import Foundation

/// Validates a remote address typed by the user before anything is fetched from it.
struct RemoteAddress {
    let text: String

    enum Problem: Error, Equatable {
        case empty
        case unsupportedScheme
        case containsCredentials
        case malformed
    }

    var result: Result<URL, Problem> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        if trimmed.hasPrefix("/") {
            return .success(URL(fileURLWithPath: trimmed))
        }
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else {
            return .failure(trimmed.contains("@") && trimmed.contains(":") ? .unsupportedScheme : .malformed)
        }
        guard ["https", "http", "file"].contains(scheme) else { return .failure(.unsupportedScheme) }
        guard url.user == nil, url.password == nil else { return .failure(.containsCredentials) }
        guard scheme == "file" || url.host?.isEmpty == false else { return .failure(.malformed) }
        return .success(url)
    }
}
