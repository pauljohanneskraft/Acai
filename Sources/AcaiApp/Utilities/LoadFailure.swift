import Foundation

/// Why a load failed, phrased by what the reader can do next: reconnect, act on GitHub's answer, or retry.
struct LoadFailure {
    let error: any Error

    var message: LocalizedStringResource {
        if let urlError = error as? URLError, urlError.isOffline {
            return .app("Error.LoadFailure.Offline")
        }
        if let failure = error as? GitHubAPIClient.Failure, failure.isActionable {
            return failure.message
        }
        return .app("Error.LoadFailure.Detail \(detail)")
    }

    /// Shown untranslated: `AcaiCore` and `AcaiGit` errors are shared with the CLI and not localized.
    private var detail: String {
        (error as? any LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

private extension URLError {
    var isOffline: Bool {
        [.notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
         .dnsLookupFailed, .timedOut].contains(code)
    }
}
