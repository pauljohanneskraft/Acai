import Foundation
import AcaiCore

/// Reads `pyproject.toml` for the directories it declares. A manifest that is absent, declares no
/// layout, or names only directories that do not exist yields none, leaving the caller on the
/// conventional `src` probe. A malformed manifest yields none plus a diagnostic — discovery must not
/// fail because a file it merely consults does not parse.
struct PythonManifest: Sendable {
    static let fileName = "pyproject.toml"

    private let root: URL

    init(root: URL) {
        self.root = root
    }

    func sourceDirectories() -> (directories: [URL], diagnostics: [ParseDiagnostic]) {
        let manifest = root.appendingPathComponent(Self.fileName)
        guard let contents = try? String(contentsOf: manifest, encoding: .utf8) else { return ([], []) }
        do {
            let declared = try PythonPackageLayout(TOMLReader(contents).parse()).declaredDirectories
            return (declared.compactMap(directory), [])
        } catch {
            return ([], [diagnostic(for: error)])
        }
    }

    /// Resolves a declared path against the manifest and keeps it only when it is a directory that
    /// stays inside the project — `package-dir = {"" = "../.."}` is external input like any other.
    private func directory(_ declared: String) -> URL? {
        let base = root.standardizedFileURL
        let candidate = base.appendingPathComponent(declared).standardizedFileURL
        guard candidate.path == base.path || candidate.path.hasPrefix(base.path + "/") else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return candidate
    }

    private func diagnostic(for error: any Error) -> ParseDiagnostic {
        let failure = error as? TOMLParseError
        let detail = failure?.message ?? "\(error)"
        return ParseDiagnostic(
            location: SourceLocation(
                filePath: Self.fileName, line: failure?.line ?? 1, column: failure?.column ?? 1),
            kind: .error,
            message: "\(Self.fileName) could not be read (\(detail)); "
                + "falling back to the conventional source layout."
        )
    }
}
