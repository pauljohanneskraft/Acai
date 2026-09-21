import AcaiGit
import Foundation

/// Equal for every spelling of one remote (`…/repo` and `…/repo.git`, any host case, with or
/// without credentials), because they all share one hub clone on disk.
struct RemoteIdentity: Hashable, Sendable {
    let rawValue: String

    init(remoteURL: URL) {
        rawValue = GitRepository(remoteURL: remoteURL, storeDirectory: URL(fileURLWithPath: "/")).identity
    }
}
