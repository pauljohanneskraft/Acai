import Foundation
import AcaiCore

/// A flat list of workspace globs, in the semantics npm, Yarn and pnpm share: a glob names package
/// directories, and a `!`-prefixed one excludes what it matches.
struct NodeWorkspaces {
    private let included: [String]
    private let excluded: [String]
    private let excludedDirectories: Set<String>

    init(globs: [String], excludingDirectories excludedDirectories: Set<String>) {
        included = globs.filter { !$0.hasPrefix("!") }
        excluded = globs.filter { $0.hasPrefix("!") }.map { String($0.dropFirst()) }
        self.excludedDirectories = excludedDirectories
    }

    /// Every directory a glob matches that is itself a package, in declaration order and de-duplicated.
    func packageRoots(in root: URL) -> [URL] {
        let excludedRoots = Set(
            excluded.flatMap { DirectoryGlob($0, excludingDirectories: excludedDirectories).directories(in: root) }
                .map(\.path))
        return included
            .flatMap { DirectoryGlob($0, excludingDirectories: excludedDirectories).directories(in: root) }
            .filter { !excludedRoots.contains($0.path) && $0.path != root.standardizedFileURL.path }
            .filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("package.json").path) }
            .removingDuplicates { $0.path }
    }
}

// MARK: - Where The Globs Come From

/// Where a Node project declares its packages. `package.json`'s `workspaces` covers npm and Yarn;
/// pnpm leaves that key out and keeps the same flat list in `pnpm-workspace.yaml`, so both are read
/// and whichever the project uses is treated the same way.
struct NodeWorkspaceDeclaration {
    /// Nil when neither file declares anything — the ordinary single-package case.
    let globs: [String]?
    let diagnostics: [ParseDiagnostic]

    init(in root: URL) {
        let manifest = NodeManifest(in: root)
        let pnpm = PnpmWorkspaceFile(in: root)
        if let declared = manifest.workspaceGlobs, !declared.isEmpty {
            globs = declared
            diagnostics = []
        } else if let declared = pnpm.packageGlobs, !declared.isEmpty {
            globs = declared
            diagnostics = manifest.diagnostics
        } else {
            globs = nil
            diagnostics = manifest.diagnostics + pnpm.diagnostics
        }
    }
}

/// A project root's `package.json`, read for the one thing workspace discovery needs from it.
///
/// A manifest that is present but will not parse is reported rather than read as "no workspaces":
/// the two are indistinguishable on disk and mean opposite things — the second is an ordinary single
/// package, the first a monorepo about to be analysed as one.
struct NodeManifest {
    private let json: [String: Any]?
    private let isPresentButUnreadable: Bool

    init(in root: URL) {
        let url = root.appendingPathComponent("package.json")
        json = JSONWithComments(contentsOf: url)?.object
        isPresentButUnreadable = json == nil && FileManager.default.fileExists(atPath: url.path)
    }

    /// Both shapes npm accepts: a bare array of globs, and the Yarn-style object holding them under
    /// `packages`. Nil when the manifest declares none, or could not be read at all.
    var workspaceGlobs: [String]? {
        switch json?["workspaces"] {
        case let values as [String]:
            return values
        case let object as [String: Any]:
            return object["packages"] as? [String]
        default:
            return nil
        }
    }

    var diagnostics: [ParseDiagnostic] {
        guard isPresentButUnreadable else { return [] }
        return [ParseDiagnostic(
            location: SourceLocation(filePath: "package.json", line: 1, column: 1),
            kind: .incompleteDiscovery,
            message: "package.json is present but could not be parsed, so any workspaces it declares were "
                + "not read. Source directories were guessed from the folder layout instead."
        )]
    }
}

/// pnpm's `pnpm-workspace.yaml`, read for its `packages:` list alone.
///
/// That list is a flat sequence of scalars — block items under the key, or an inline flow sequence
/// on it — which a line reader handles exactly, so supporting pnpm costs no YAML dependency.
/// Anything richer than those two shapes is reported rather than half-read.
struct PnpmWorkspaceFile {
    /// Nil when the file is absent, unreadable, or declares no `packages:` list.
    let packageGlobs: [String]?
    private let isPresent: Bool

    init(in root: URL) {
        let url = root.appendingPathComponent("pnpm-workspace.yaml")
        isPresent = FileManager.default.fileExists(atPath: url.path)
        packageGlobs = (try? String(contentsOf: url, encoding: .utf8)).flatMap {
            PnpmPackagesKey($0).globs
        }
    }

    var diagnostics: [ParseDiagnostic] {
        guard isPresent, packageGlobs == nil else { return [] }
        return [ParseDiagnostic(
            location: SourceLocation(filePath: "pnpm-workspace.yaml", line: 1, column: 1),
            kind: .incompleteDiscovery,
            message: "pnpm-workspace.yaml is present but no `packages:` list could be read from it, so the "
                + "workspace's packages are unknown. Source directories were guessed from the folder layout "
                + "instead."
        )]
    }
}

/// The `packages:` entry of a `pnpm-workspace.yaml`, in the two spellings a flat scalar sequence has.
struct PnpmPackagesKey {
    private let lines: [String]

    init(_ text: String) {
        lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    var globs: [String]? {
        guard let keyIndex = lines.firstIndex(where: { $0.hasPrefix("packages:") }) else { return nil }
        let inline = lines[keyIndex].dropFirst("packages:".count).trimmingCharacters(in: .whitespaces)
        if inline.hasPrefix("[") { return flowSequence(inline) }
        guard inline.isEmpty || inline.hasPrefix("#") else { return nil }
        return blockItems(after: keyIndex)
    }

    /// `- 'packages/*'` items indented under the key, up to the first line that is neither an item,
    /// a comment nor blank — the end of the sequence.
    private func blockItems(after keyIndex: Int) -> [String]? {
        var items: [String] = []
        for line in lines[lines.index(after: keyIndex)...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            guard line.first?.isWhitespace == true, trimmed.hasPrefix("- ") else { break }
            let value = unquoted(String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces))
            guard !value.isEmpty else { return nil }
            items.append(value)
        }
        return items.isEmpty ? nil : items
    }

    private func flowSequence(_ value: String) -> [String]? {
        guard let close = value.lastIndex(of: "]") else { return nil }
        let items = value[value.index(after: value.startIndex)..<close]
            .split(separator: ",")
            .map { unquoted($0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.isEmpty }
        return items.isEmpty ? nil : items
    }

    private func unquoted(_ value: String) -> String {
        for quote in ["'", "\""] where value.count >= 2 && value.hasPrefix(quote) && value.hasSuffix(quote) {
            return String(value.dropFirst().dropLast())
        }
        return value
    }
}
