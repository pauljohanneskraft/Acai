import Foundation

/// The `.gitignore` rules in effect under a project root, as the path predicate
/// ``AnalysisService/analyzeProject(at:allowedLanguages:respectingGitignore:includingFile:)``
/// applies before a file is read.
///
/// Agnostic by construction: `.gitignore` is a property of the repository, and this names no
/// language, tool or manifest.
///
/// Every rule the walk could not read is reported through ``diagnostics`` rather than dropped, so a
/// typo in a `.gitignore` surfaces in the health report instead of silently removing source from
/// the analysis.
public struct GitignoreFilter: Sendable {

    private struct File: Sendable {
        /// The holding directory's path components, relative to the project root.
        let directory: [String]
        let patterns: [GitignorePattern]
    }

    /// Ceilings on what a repository's own files can make this cost. Both are far above any real
    /// project and exist so an analyzed repository cannot stall discovery.
    private static let maximumFiles = 4096
    private static let maximumLinesPerFile = 10_000

    private let files: [File]

    /// Problems found while reading the rules, each located at the `.gitignore` line it came from.
    public let diagnostics: [ParseDiagnostic]

    public init(
        root: URL,
        excludingDirectories: Set<String> = AcaiConstants.standard.defaultExcludedSourceDirectories,
        fileManager: FileManager = .default
    ) {
        var files: [File] = []
        var diagnostics: [ParseDiagnostic] = []
        DirectoryTreeWalk(excludedDirectories: excludingDirectories, fileManager: fileManager)
            .walk(from: root) { directory, entries in
                guard files.count < Self.maximumFiles else { return }
                guard let source = entries.first(where: { $0.lastPathComponent == ".gitignore" }) else { return }
                let read = Reading(file: source, relativePath: source.relativePath(from: root))
                diagnostics.append(contentsOf: read.diagnostics)
                guard !read.patterns.isEmpty else { return }
                files.append(File(
                    directory: directory.relativePath(from: root).split(separator: "/").map(String.init),
                    patterns: read.patterns
                ))
            }
        // Shallowest first, so a nested `.gitignore` is evaluated last and therefore wins.
        self.files = files.sorted { $0.directory.count < $1.directory.count }
        self.diagnostics = diagnostics
    }

    /// `false` when git would ignore this root-relative path. A path inside an ignored directory is
    /// ignored whatever its own rules say, because git never descends into one — so a negation can
    /// only re-include a file whose directories are all still included.
    public func includes(_ relativePath: String) -> Bool {
        guard !files.isEmpty else { return true }
        let components = relativePath.split(separator: "/")
        guard !components.isEmpty else { return true }
        for end in 1...components.count where isIgnored(components[0..<end], isDirectory: end < components.count) {
            return false
        }
        return true
    }

    private func isIgnored(_ path: ArraySlice<Substring>, isDirectory: Bool) -> Bool {
        var isIgnored = false
        for file in files where covers(file, path) {
            let relative = path.dropFirst(file.directory.count)
            guard !relative.isEmpty else { continue }
            // Within one file the last matching rule wins, so this keeps overwriting rather than
            // stopping at the first match.
            for pattern in file.patterns where pattern.matches(relative, isDirectory: isDirectory) {
                isIgnored = !pattern.isNegated
            }
        }
        return isIgnored
    }

    private func covers(_ file: File, _ path: ArraySlice<Substring>) -> Bool {
        guard file.directory.count < path.count else { return false }
        for (offset, component) in file.directory.enumerated()
        where path[path.startIndex + offset] != Substring(component) {
            return false
        }
        return true
    }
}

extension GitignoreFilter {
    /// One `.gitignore` read from disk: the rules it yielded and the lines it could not.
    private struct Reading: Sendable {
        let patterns: [GitignorePattern]
        let diagnostics: [ParseDiagnostic]

        init(file: URL, relativePath: String) {
            guard let contents = try? String(contentsOf: file, encoding: .utf8) else {
                patterns = []
                diagnostics = [ParseDiagnostic(
                    location: SourceLocation(filePath: relativePath, line: 0, column: 0),
                    kind: .unreadable,
                    message: "ignore rules could not be read; nothing was excluded by it"
                )]
                return
            }
            var patterns: [GitignorePattern] = []
            var diagnostics: [ParseDiagnostic] = []
            let lines = contents.split(separator: "\n", omittingEmptySubsequences: false)
            for (offset, line) in lines.prefix(GitignoreFilter.maximumLinesPerFile).enumerated() {
                let text = line.hasSuffix("\r") ? String(line.dropLast()) : String(line)
                switch GitignoreLine(text: text).outcome {
                case .none:
                    continue
                case .rule(let pattern, let problem):
                    patterns.append(pattern)
                    guard let problem else { continue }
                    diagnostics.append(ParseDiagnostic(
                        location: SourceLocation(filePath: relativePath, line: offset + 1, column: 0),
                        kind: .invalidPattern, message: problem
                    ))
                case .refused(let reason):
                    diagnostics.append(ParseDiagnostic(
                        location: SourceLocation(filePath: relativePath, line: offset + 1, column: 0),
                        kind: .invalidPattern, message: "\(reason); the rule was skipped"
                    ))
                }
            }
            self.patterns = patterns
            self.diagnostics = diagnostics
        }
    }
}
