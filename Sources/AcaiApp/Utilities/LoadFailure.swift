import Foundation

/// Why a load failed, in terms the reader can act on. A dropped connection, a request the server
/// rejected and a spent rate limit each need a different next step, and `try?` collapsed all of
/// them into an empty result that read as "there is nothing here".
struct LoadFailure {
    let error: any Error

    var message: LocalizedStringResource {
        if let urlError = error as? URLError, urlError.isOffline {
            return .app("Error.LoadFailure.Offline")
        }
        return .app("Error.LoadFailure.Detail \(detail)")
    }

    /// `AcaiCore` and `AcaiGit` are shared with the CLI and are not localized, so their text shows
    /// untranslated inside the localized frame rather than in place of it.
    private var detail: String {
        (error as? any LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

private extension URLError {
    /// Every code that means "the request never reached a server", so the message can promise that
    /// retrying once there is a connection will work.
    var isOffline: Bool {
        [.notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
         .dnsLookupFailed, .timedOut].contains(code)
    }
}
