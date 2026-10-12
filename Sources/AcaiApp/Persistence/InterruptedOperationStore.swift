import Foundation

/// Reads and writes `ActivityCenter`'s ledger as one small JSON file beside the project files,
/// atomically (temp file + rename, via `Data.write(options: .atomic)`) — a process killed
/// mid-write leaves the previous ledger rather than a truncated one, which is the only failure
/// this file exists to survive.
struct InterruptedOperationStore: Sendable {
    let baseDir: URL

    private var directory: URL { baseDir.appendingPathComponent("activity", isDirectory: true) }
    var fileURL: URL { directory.appendingPathComponent("ledger.json") }

    /// A ledger this build can't read is dropped, not migrated: the cost is one launch's
    /// interruption report, against a decode shim for a shape the app no longer writes.
    func load() -> ActivityLedger {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(ActivityLedger.self, from: data),
              decoded.formatVersion == ActivityLedger.currentFormatVersion
        else { return ActivityLedger() }
        return decoded
    }

    func save(_ ledger: ActivityLedger) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(ledger).write(to: fileURL, options: .atomic)
    }
}
