import AcaiGit
import Foundation

/// What survives termination of an operation that was still running: how to resume it, and nothing more.
struct InterruptedOperationRecord: Codable, Equatable, Identifiable, Sendable {
    /// The work to redo, carrying everything needed to redo it after a relaunch.
    enum Resumption: Codable, Hashable, Sendable {
        case reindex(codebaseID: UUID)
        case pull(codebaseID: UUID)
        case switchRef(codebaseID: UUID, ref: String, refKind: GitCheckout.Ref.Kind)
        case clone(RemoteCloneRequest)

        /// The codebase the work was for; a clone's is the one it would have added.
        var codebaseID: UUID {
            switch self {
            case .reindex(let codebaseID), .pull(let codebaseID), .switchRef(let codebaseID, _, _):
                codebaseID
            case .clone(let request):
                request.codebaseID
            }
        }

        /// Whether finishing this work leaves `other`'s target consistent again.
        func resolves(_ other: Self) -> Bool {
            guard codebaseID == other.codebaseID else { return false }
            switch (self, other) {
            case (.reindex, .reindex), (.pull, .pull), (.clone, .clone), (.switchRef, .pull), (.switchRef, .switchRef):
                return true
            default:
                return false
            }
        }
    }

    /// A clone, as the add-codebase sheet asked for it.
    struct RemoteCloneRequest: Codable, Hashable, Sendable {
        var projectID: UUID
        var codebaseID: UUID
        var name: String
        var remoteURL: URL
        var ref: String
        var refKind: GitCheckout.Ref.Kind
        var latestSnapshotOnly: Bool

        var depth: GitHistoryDepth { latestSnapshotOnly ? .latestSnapshot : .full }
    }

    var id: UUID
    var kind: ActivityOperation.Kind
    var resumption: Resumption
    var startedAt: Date
}

/// `ActivityCenter`'s on-disk state: what is running now, and what an earlier launch never finished.
struct ActivityLedger: Codable, Equatable, Sendable {
    static let currentFormatVersion = 1

    var formatVersion = Self.currentFormatVersion
    var inFlight: [InterruptedOperationRecord] = []
    var interrupted: [InterruptedOperationRecord] = []
}
