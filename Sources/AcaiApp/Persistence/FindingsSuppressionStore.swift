import Foundation

/// Reads/writes one project's `FindingsSuppressionBaseline` to a plain JSON file — sorted-keys,
/// pretty-printed encoding so the file stays diffable/git-reviewable, atomic writes (temp file +
/// rename, via `Data.write(options: .atomic)`) so a suppress/un-suppress action can never leave a
/// half-written file behind if the app is killed mid-write.
struct FindingsSuppressionStore: Sendable {
    let baseDir: URL

    private var suppressionsDir: URL {
        baseDir.appendingPathComponent("suppressions", isDirectory: true)
    }

    private func url(forProject projectID: UUID) -> URL {
        suppressionsDir.appendingPathComponent("\(projectID.uuidString).json")
    }

    /// Loads a project's baseline off the main actor — call from a background `Task`. Returns an
    /// empty baseline (not an error) when nothing has been suppressed yet, or when the file can't
    /// be read/decoded — a suppression baseline missing or stale is never a reason to block the
    /// Findings view itself.
    func load(projectID: UUID) -> FindingsSuppressionBaseline {
        guard let data = try? Data(contentsOf: url(forProject: projectID)),
              let decoded = try? JSONDecoder().decode(FindingsSuppressionBaseline.self, from: data),
              decoded.formatVersion >= 1
        else { return FindingsSuppressionBaseline() }
        return decoded
    }

    /// Writes a project's baseline off the main actor — call from a background `Task`.
    func save(_ baseline: FindingsSuppressionBaseline, projectID: UUID) throws {
        try FileManager.default.createDirectory(at: suppressionsDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(baseline)
        try data.write(to: url(forProject: projectID), options: .atomic)
    }
}
