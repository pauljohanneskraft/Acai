import Foundation

/// `ActivityCenter`'s ledger as one JSON file beside the project files, written atomically.
struct InterruptedOperationStore: Sendable {
    let baseDir: URL

    private var directory: URL { baseDir.appendingPathComponent("activity", isDirectory: true) }
    var fileURL: URL { directory.appendingPathComponent("ledger.json") }

    /// A ledger this build can't read is dropped, not migrated.
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
