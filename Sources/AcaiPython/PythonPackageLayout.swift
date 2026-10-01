import AcaiCore

/// The source directories a `pyproject.toml` declares, across the four packaging tools that state a
/// layout: setuptools (`package-dir`, `packages.find.where`), poetry (`packages`) and hatch
/// (`build.targets.wheel.packages`). Paths are returned as written, relative to the manifest.
struct PythonPackageLayout: Sendable {
    private let document: TOMLValue

    init(_ document: TOMLValue) {
        self.document = document
    }

    var declaredDirectories: [String] {
        (setuptoolsPackageDirs + setuptoolsFindWhere + poetryPackageDirs + hatchPackages)
            .removingDuplicates { $0 }
    }

    /// `package-dir = {"" = "lib"}` maps package names to directories; the directories are the values.
    /// Sorted by package name so a dictionary's ordering cannot reach the result.
    private var setuptoolsPackageDirs: [String] {
        guard let table = document.value(at: ["tool", "setuptools", "package-dir"])?.tableValue else {
            return []
        }
        return table.sorted { $0.key < $1.key }.compactMap { $0.value.stringValue }
    }

    private var setuptoolsFindWhere: [String] {
        strings(at: ["tool", "setuptools", "packages", "find", "where"])
    }

    /// `packages = [{include = "mypkg", from = "libs"}]` — `from` is the directory when present,
    /// otherwise `include` names one directly.
    private var poetryPackageDirs: [String] {
        guard let entries = document.value(at: ["tool", "poetry", "packages"])?.arrayValue else {
            return []
        }
        return entries.compactMap { entry in
            guard let table = entry.tableValue else { return nil }
            if let from = table["from"]?.stringValue { return from }
            return table["include"]?.stringValue.flatMap(directoryPrefix)
        }
    }

    private var hatchPackages: [String] {
        strings(at: ["tool", "hatch", "build", "targets", "wheel", "packages"])
    }

    private func strings(at path: [String]) -> [String] {
        document.value(at: path)?.arrayValue?.compactMap(\.stringValue) ?? []
    }

    /// The directory part of a poetry `include`, which may be a glob (`my_package/**/*.py`).
    private func directoryPrefix(of pattern: String) -> String? {
        guard let star = pattern.firstIndex(of: "*") else { return pattern }
        let prefix = pattern[..<star]
        guard let slash = prefix.lastIndex(of: "/") else { return nil }
        return String(prefix[..<slash])
    }
}
