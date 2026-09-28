import AcaiGit
import Foundation

struct PendingClone: Equatable {
    var name: String
    var remoteURL: URL
    var ref: GitCheckout.Ref
    var sizeKilobytes: Int?
}
