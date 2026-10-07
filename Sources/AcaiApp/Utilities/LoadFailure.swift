import Foundation

/// Why a load failed, phrased by what the reader can do next: reconnect, wait, act on GitHub's answer, or retry.
struct LoadFailure {
    let error: any Error

    private enum Cause {
        case offline
        case serverUnresponsive
        case gitHub(GitHubAPIClient.Failure)
        case unexpected
    }

    private var cause: Cause {
        if let urlError = error as? URLError {
            if urlError.isOffline { return .offline }
            if urlError.isServerUnresponsive { return .serverUnresponsive }
        }
        if let failure = error as? GitHubAPIClient.Failure, failure.isActionable { return .gitHub(failure) }
        return .unexpected
    }

    var message: LocalizedStringResource {
        switch cause {
        case .offline:
            .app("Error.LoadFailure.Offline")
        case .serverUnresponsive:
            .app("Error.LoadFailure.ServerUnresponsive")
        case .gitHub(let failure):
            failure.message
        case .unexpected:
            .app("Error.LoadFailure.Unexpected")
        }
    }

    /// Only an unexpected failure has one; untranslated, since `AcaiCore` and `AcaiGit` aren't localized.
    var detail: String? {
        guard case .unexpected = cause else { return nil }
        return (error as? any LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

private extension URLError {
    var isOffline: Bool {
        [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff,
         .cannotFindHost, .dnsLookupFailed].contains(code)
    }

    var isServerUnresponsive: Bool {
        [.timedOut, .cannotConnectToHost].contains(code)
    }
}
