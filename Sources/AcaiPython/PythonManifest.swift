import Foundation
import AcaiCore

/// Reads `pyproject.toml` for the directories it declares. A manifest that is absent, declares no
/// layout, or names no usable directory yields none, leaving the caller on the conventional `src`
/// probe. A malformed manifest, or a declared path that does not exist or leads outside the project,
/// yields a diagnostic — discovery must not fail because a file it merely consults is wrong.
struct PythonManifest: Sendable {
    private enum DeclaredDirectory {
        case usable(URL)
        case missing
        case outsideProject
    }

    private let fileName = "pyproject.toml"
    private let root: URL

    init(root: URL) {
        self.root = root
    }

    func sourceDirectories() -> (directories: [URL], diagnostics: [ParseDiagnostic]) {
        let manifest = root.appendingPathComponent(fileName)
        guard let contents = try? String(contentsOf: manifest, encoding: .utf8) else { return ([], []) }
        let declared: [String]
        do {
            declared = try PythonPackageLayout(TOMLReader(contents).parse()).declaredDirectories
        } catch {
            return ([], [diagnostic(for: error)])
        }
        var directories: [URL] = []
        var diagnostics: [ParseDiagnostic] = []
        for path in declared {
            switch directory(path) {
            case .usable(let url):
                directories.append(url)
            case .missing:
                diagnostics.append(diagnostic("declares '\(path)' as a source directory, but it does not exist"))
            case .outsideProject:
                diagnostics.append(diagnostic("declares '\(path)' as a source directory outside the project"))
            }
        }
        return (directories, diagnostics)
    }

    /// Containment is checked with symlinks resolved on both sides, so a link inside the project
    /// cannot lead discovery out of it. The returned URL stays unresolved, relative to `root`.
    private func directory(_ declared: String) -> DeclaredDirectory {
        let base = root.standardizedFileURL
        let candidate = base.appendingPathComponent(declared).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return .missing }
        let resolvedBase = base.resolvingSymlinksInPath().path
        let resolved = candidate.resolvingSymlinksInPath().path
        guard resolved == resolvedBase || resolved.hasPrefix(resolvedBase + "/") else { return .outsideProject }
        return .usable(candidate)
    }

    private func diagnostic(for error: any Error) -> ParseDiagnostic {
        let failure = error as? TOMLParseError
        let detail = failure?.message ?? "\(error)"
        return diagnostic(
            "could not be read (\(detail)); falling back to the conventional source layout",
            line: failure?.line ?? 1, column: failure?.column ?? 1)
    }

    private func diagnostic(_ problem: String, line: Int = 1, column: Int = 1) -> ParseDiagnostic {
        ParseDiagnostic(
            location: SourceLocation(filePath: fileName, line: line, column: column),
            kind: .incompleteDiscovery,
            message: "\(fileName) \(problem)."
        )
    }
}
