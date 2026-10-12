import Foundation

/// What survives termination of an operation that was still running: enough to name the subject
/// the interruption left half-updated, and nothing a later launch would have to migrate.
struct InterruptedOperationRecord: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var kind: ActivityOperation.Kind
    var subject: ActivityOperation.Subject
    var startedAt: Date

    init(id: UUID, kind: ActivityOperation.Kind, subject: ActivityOperation.Subject, startedAt: Date) {
        self.id = id
        self.kind = kind
        self.subject = subject
        self.startedAt = startedAt
    }

    init(_ operation: ActivityOperation) {
        self.init(id: operation.id, kind: operation.kind, subject: operation.subject, startedAt: operation.startedAt)
    }
}

/// The two halves of what `ActivityCenter` keeps on disk: what is running now, and what an earlier
/// launch never finished. A launch turns the first into the second — the whole mechanism by which
/// a termination mid-index becomes something the user can see and act on.
struct ActivityLedger: Codable, Equatable, Sendable {
    static let currentFormatVersion = 1

    var formatVersion = Self.currentFormatVersion
    var inFlight: [InterruptedOperationRecord] = []
    var interrupted: [InterruptedOperationRecord] = []
}
