import Foundation

/// Reads/writes one project's `FilterPresetList` to a plain JSON file — sorted-keys,
/// pretty-printed encoding so the file stays diffable/git-reviewable, atomic writes (temp file +
/// rename, via `Data.write(options: .atomic)`) so a save can never leave a half-written file
/// behind if the app is killed mid-write. A small, self-contained type (its own directory under
/// the same `baseDir` `ProjectStore` already uses, rather than a new method added to
/// `ProjectStore` itself) so it doesn't touch that shared, heavily-used file — same shape as
/// `FindingsSuppressionStore`.
///
/// A value you instantiate over a `baseDir` and call instance methods on — never a static-function
/// namespace.
struct FilterPresetStore: Sendable {
    let baseDir: URL

    private var presetsDir: URL {
        baseDir.appendingPathComponent("filterPresets", isDirectory: true)
    }

    private func url(forProject projectID: UUID) -> URL {
        presetsDir.appendingPathComponent("\(projectID.uuidString).json")
    }

    /// Loads a project's saved presets off the main actor — call from a background `Task`. Returns
    /// an empty list (not an error) when nothing has been saved yet, or when the file can't be
    /// read/decoded — a missing or corrupt preset file is never a reason to block a diagram's
    /// Filter section.
    func load(projectID: UUID) -> FilterPresetList {
        guard let data = try? Data(contentsOf: url(forProject: projectID)),
              let decoded = try? JSONDecoder().decode(FilterPresetList.self, from: data),
              decoded.formatVersion <= FilterPresetList.currentFormatVersion
        else { return FilterPresetList() }
        return decoded
    }

    /// Writes a project's presets off the main actor — call from a background `Task`.
    func save(_ list: FilterPresetList, projectID: UUID) throws {
        try FileManager.default.createDirectory(at: presetsDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(list)
        try data.write(to: url(forProject: projectID), options: .atomic)
    }
}
