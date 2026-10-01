import Foundation
import AcaiCore

/// The `tsconfig.json` fields source discovery needs, with every path already resolved against the
/// file it was written in — `tsc` resolves a relative path against its originating file, so an
/// inherited `include` still points into the base file's own folder.
struct TypeScriptConfiguration {
    var rootDir: URL?
    /// The literal directory prefix of each `include` pattern. Nil when the file declares none, which
    /// is what lets an inherited `include` survive the merge.
    var includeDirs: [URL]?
    /// Each `references[].path`, resolved to the referenced project's configuration file.
    var referencedConfigurations: [URL]?
    /// Each `extends` entry, resolved to a file on disk, in the order `tsc` applies them.
    var extendedConfigurations: [URL] = []
    /// Each `extends` entry that named nothing on disk — a base package that is not installed, or
    /// one hoisted above the analysed folder. Whatever it declared is missing from this merge.
    var unresolvedExtends: [String] = []

    var sourceDirs: [URL] { (rootDir.map { [$0] } ?? []) + (includeDirs ?? []) }

    /// `tsc`'s `extends` merge: a field the nearer file declares replaces the inherited one outright
    /// rather than adding to it.
    func overriding(_ base: TypeScriptConfiguration) -> TypeScriptConfiguration {
        TypeScriptConfiguration(
            rootDir: rootDir ?? base.rootDir,
            includeDirs: includeDirs ?? base.includeDirs,
            referencedConfigurations: referencedConfigurations ?? base.referencedConfigurations,
            extendedConfigurations: extendedConfigurations
        )
    }
}

extension TypeScriptConfiguration {
    /// Nil when the file is missing or is not an object even once its comments and trailing commas
    /// are gone; an unrecognised shape for one field only leaves that field unset.
    init?(contentsOf url: URL, notAbove ceiling: URL) {
        guard let json = JSONWithComments(contentsOf: url)?.object else { return nil }
        let directory = url.deletingLastPathComponent()

        let extendsValues: [String]
        switch json["extends"] {
        case let value as String:
            extendsValues = [value]
        case let values as [String]:
            extendsValues = values
        default:
            extendsValues = []
        }
        let resolvedExtends = extendsValues.map {
            ($0, TypeScriptConfigurationPath($0, referredToBy: url, notAbove: ceiling).url)
        }
        extendedConfigurations = resolvedExtends.compactMap(\.1)
        unresolvedExtends = resolvedExtends.filter { $0.1 == nil }.map(\.0)

        if let compilerOptions = json["compilerOptions"] as? [String: Any],
           let declared = compilerOptions["rootDir"] as? String {
            rootDir = directory.appendingPathComponent(declared).standardizedFileURL
        }

        if let includes = json["include"] as? [String] {
            // Only the leading literal components can name a directory; `src/**/*.ts` is `src`, and a
            // pattern that starts with a wildcard (`**/*.ts`) is the config's own folder.
            includeDirs = includes.map { pattern in
                let literalPrefix = pattern.components(separatedBy: "/")
                    .prefix { !$0.contains("*") && !$0.contains("?") && !$0.isEmpty }
                return directory.appendingPathComponent(literalPrefix.joined(separator: "/")).standardizedFileURL
            }
        }

        if let references = json["references"] as? [[String: Any]] {
            referencedConfigurations = references
                .compactMap { $0["path"] as? String }
                .compactMap { TypeScriptConfigurationPath($0, referredToBy: url, notAbove: ceiling).url }
        }
    }
}

// MARK: - Resolving One Reference

/// Resolves a path a `tsconfig.json` points at — an `extends` target or a `references[].path` — to
/// the configuration file it names, the way `tsc` does: a relative path, a path whose `.json` is
/// left off, a directory standing for its own `tsconfig.json`, or a bare package name looked up in
/// `node_modules` from the referring file's folder upwards.
struct TypeScriptConfigurationPath {
    private let value: String
    private let referrer: URL
    /// The walk up towards `node_modules` stops here, so resolution never leaves the project.
    private let ceiling: URL

    init(_ value: String, referredToBy referrer: URL, notAbove ceiling: URL) {
        self.value = value
        self.referrer = referrer.standardizedFileURL
        self.ceiling = ceiling.standardizedFileURL
    }

    var url: URL? {
        isPath ? pathURL : packageURL
    }

    private var isPath: Bool {
        value.hasPrefix("./") || value.hasPrefix("../") || value.hasPrefix("/")
            || value == "." || value == ".."
    }

    private var pathURL: URL? {
        let candidate = value.hasPrefix("/")
            ? URL(fileURLWithPath: value)
            : referrer.deletingLastPathComponent().appendingPathComponent(value)
        return configuration(at: candidate)
    }

    private var packageURL: URL? {
        var directory = referrer.deletingLastPathComponent()
        while true {
            let candidate = directory.appendingPathComponent("node_modules").appendingPathComponent(value)
            if let url = configuration(at: candidate) { return url }
            guard directory.path.hasPrefix(ceiling.path + "/") else { return nil }
            directory = directory.deletingLastPathComponent().standardizedFileURL
        }
    }

    /// `candidate` itself when it is a configuration file, its `tsconfig.json` when it is a directory,
    /// or `candidate.json` when the extension was left off.
    private func configuration(at candidate: URL) -> URL? {
        let standardized = candidate.standardizedFileURL
        var isDirectory = ObjCBool(false)
        if FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else { return standardized }
            let nested = standardized.appendingPathComponent("tsconfig.json")
            return FileManager.default.fileExists(atPath: nested.path) ? nested : nil
        }
        guard standardized.pathExtension != "json" else { return nil }
        let suffixed = standardized.appendingPathExtension("json")
        return FileManager.default.fileExists(atPath: suffixed.path) ? suffixed : nil
    }
}

// MARK: - Walking the Project Graph

/// Reads a project's `tsconfig.json`, the whole `extends` chain behind it and every project it
/// `references`, and reports the source directories they declare between them.
///
/// A configuration file that reappears while its own chain is still being resolved is a cycle: the
/// walk stops there and records a diagnostic, so a `tsconfig` that extends or references itself round
/// a loop ends the read instead of hanging. A file reached twice by separate paths — one base shared
/// by several projects — is not a cycle and is read each time it is extended.
final class TypeScriptProjectReader {
    private let ceiling: URL
    /// Projects whose directories are already in the result, so a references diamond contributes once.
    private var resolvedProjects: Set<String> = []
    private(set) var diagnostics: [ParseDiagnostic] = []

    init(notAbove ceiling: URL) {
        self.ceiling = ceiling.standardizedFileURL
    }

    /// The directories the project in `directory` declares, or nil when it has no `tsconfig.json` that
    /// names any — the signal to fall back to probing the filesystem.
    func sourceDirs(ofProjectIn directory: URL) -> [URL]? {
        let url = directory.appendingPathComponent("tsconfig.json").standardizedFileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let dirs = sourceDirs(ofProjectAt: url, referencedBy: []).removingDuplicates { $0.path }
        return dirs.isEmpty ? nil : dirs
    }

    private func sourceDirs(ofProjectAt url: URL, referencedBy chain: Set<String>) -> [URL] {
        guard !chain.contains(url.path) else {
            record(cycleAt: url, through: "references")
            return []
        }
        guard resolvedProjects.insert(url.path).inserted else { return [] }
        guard let configuration = flattened(configurationAt: url, extendedBy: []) else { return [] }
        var dirs = configuration.sourceDirs.filter(\.isExistingDirectory)
        for reference in configuration.referencedConfigurations ?? [] {
            dirs += sourceDirs(ofProjectAt: reference, referencedBy: chain.union([url.path]))
        }
        return dirs
    }

    /// One configuration with its `extends` chain applied beneath it. A later `extends` entry wins
    /// over an earlier one, and the file's own fields win over all of them.
    private func flattened(
        configurationAt url: URL, extendedBy chain: Set<String>
    ) -> TypeScriptConfiguration? {
        guard !chain.contains(url.path) else {
            record(cycleAt: url, through: "extends")
            return nil
        }
        guard let configuration = TypeScriptConfiguration(contentsOf: url, notAbove: ceiling) else {
            record(unreadable: url)
            return nil
        }
        for unresolved in configuration.unresolvedExtends {
            record(unresolvedExtends: unresolved, in: url)
        }
        var inherited = TypeScriptConfiguration()
        for extended in configuration.extendedConfigurations {
            guard let base = flattened(configurationAt: extended, extendedBy: chain.union([url.path]))
            else { continue }
            inherited = base.overriding(inherited)
        }
        return configuration.overriding(inherited)
    }

    private func record(cycleAt url: URL, through relation: String) {
        record(
            at: url,
            message: "`\(relation)` in \(relativePath(of: url)) leads back to a configuration already "
                + "being read. The chain was not followed round again, so some configured source "
                + "directories may be missing."
        )
    }

    private func record(unreadable url: URL) {
        record(
            at: url,
            message: "\(relativePath(of: url)) is present but could not be parsed, so the source "
                + "directories it configures were not read."
        )
    }

    private func record(unresolvedExtends value: String, in url: URL) {
        record(
            at: url,
            message: "`extends` in \(relativePath(of: url)) names `\(value)`, which resolves to nothing "
                + "inside the analysed folder — an uninstalled base configuration, or one hoisted above "
                + "it. Whatever source directories it declares are missing."
        )
    }

    private func record(at url: URL, message: String) {
        diagnostics.append(ParseDiagnostic(
            location: SourceLocation(filePath: relativePath(of: url), line: 1, column: 1),
            kind: .incompleteDiscovery,
            message: message
        ))
    }

    private func relativePath(of url: URL) -> String {
        url.path.hasPrefix(ceiling.path + "/")
            ? String(url.path.dropFirst(ceiling.path.count + 1))
            : url.lastPathComponent
    }
}

extension URL {
    fileprivate var isExistingDirectory: Bool {
        (try? resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }
}
