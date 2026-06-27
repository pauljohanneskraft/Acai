/// The persisted settings for an architecture-conformance check: the path to its YAML rules file.
/// The check itself is recomputed from the codebase artifact each time the report is opened, so
/// only the rules-file location is stored (mirroring how `Codebase` stores a plain `directoryPath`).
struct ArchitectureCheckConfiguration: Codable, Hashable, Sendable {
    var rulesPath: String = ""
}
