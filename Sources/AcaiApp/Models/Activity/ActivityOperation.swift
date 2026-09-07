import Foundation
import SwiftUI

/// Purely a display+bookkeeping value; the actual work lives wherever `ActivityCenter.run` was
/// called from.
struct ActivityOperation: Identifiable, Sendable {
    enum Kind: Sendable {
        case reindex
        case gitFetch
        case gitClone
        case other(systemImage: String)

        var systemImage: String {
            switch self {
            case .reindex:
                "arrow.triangle.2.circlepath"
            case .gitFetch:
                "arrow.down.circle"
            case .gitClone:
                "square.and.arrow.down"
            case .other(let systemImage):
                systemImage
            }
        }
    }

    enum Subject: Hashable, Sendable {
        case codebase(UUID)
        case repository(URL)
        case none
    }

    var id = UUID()
    var title: LocalizedStringResource
    var kind: Kind
    var subject: Subject
    /// `nil` = indeterminate.
    var progress: Double?
    var startedAt: Date = Date()
    var requestCancel: @Sendable () -> Void
}

/// `@unchecked Sendable`: `NSLock` already provides the exclusion `advance(to:)` needs across the
/// arbitrary threads libgit2 calls back on.
final class ActivityProgressGate: @unchecked Sendable {
    private let lock = NSLock()
    private var lastReported = -1.0

    func advance(to value: Double) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard value - lastReported >= 0.01 || value >= 1 else { return false }
        lastReported = value
        return true
    }
}
