import Foundation

/// A Gradle settings file's project layout, read from the file rather than inferred from the directory
/// tree. A module sitting on disk that nothing `include`s is not one Gradle builds, and a module whose
/// `projectDir` is redirected does not live where its path suggests.
struct GradleSettings {

    private let script: GradleScript

    init(source: String) {
        script = GradleScript(source: source)
    }

    /// Whether every `include` in the file could be read literally. A build that computes part of its
    /// module list — `include(":${it.name}")`, `listFiles().forEach { include(it.name) }` — names
    /// modules this reader cannot resolve, so its answer is a floor rather than the whole set and the
    /// caller must not switch the directory scan off on the strength of it.
    var namesEveryModule: Bool {
        script.statements(after: "include").allSatisfy { statement in
            let literals = statement.quotedLiterals
            return !literals.isEmpty && literals.allSatisfy { !$0.contains("$") }
        }
    }

    /// The directory of every included module, resolved against `root` through any `projectDir`
    /// redirect. The root project is not among them, since a caller always holds it already.
    func moduleDirectories(relativeTo root: URL) -> [URL] {
        let redirects = projectDirectoryRedirects
        return includedProjectPaths.map { path in
            let segments = path.split(separator: ":").map(String.init)
            for depth in stride(from: segments.count, through: 1, by: -1) {
                let ancestor = segments.prefix(depth).joined(separator: ":")
                guard let redirect = redirects[ancestor] else { continue }
                return segments.dropFirst(depth)
                    .reduce(redirect.directory(relativeTo: root)) { $0.appending(path: $1) }
            }
            return segments.reduce(root) { $0.appending(path: $1) }
        }
    }

    /// `include(":a", ":b")`, `include ':a'` and `include("a")` all name a module path, whose colons
    /// separate it from the root project and from its parent rather than forming part of a name.
    private var includedProjectPaths: [String] {
        script.statements(after: "include")
            .flatMap(\.quotedLiterals)
            .map { $0.projectPath }
            .filter { !$0.isEmpty }
            .uniqued()
    }

    /// `project(":x").projectDir = file("…")`, keyed by project path.
    private var projectDirectoryRedirects: [String: String] {
        var redirects: [String: String] = [:]
        for statement in script.statements(after: "project") {
            let literals = statement.quotedLiterals
            guard statement.contains(word: "projectDir"), literals.count >= 2 else { continue }
            redirects[literals[0].projectPath] = literals[1]
        }
        return redirects
    }
}

private extension String {

    /// A module path with its leading colons dropped: `:core:api` and `core:api` name the same module.
    var projectPath: String {
        String(drop(while: { $0 == ":" }))
    }

    /// The directory a `file("…")` argument names. `$rootDir` and `$settingsDir`, braced or not, are
    /// both the settings file's own directory, so they resolve away rather than becoming a path
    /// component that exists nowhere; an absolute path is taken as it stands.
    func directory(relativeTo root: URL) -> URL {
        guard !hasPrefix("/") else { return URL(filePath: self) }
        let relative = withoutRootDirectoryPrefix
        return relative.isEmpty ? root : root.appending(path: relative)
    }

    private var withoutRootDirectoryPrefix: String {
        let prefixes = ["${rootDir}", "$rootDir", "${settingsDir}", "$settingsDir"]
        let body = prefixes.first(where: hasPrefix).map { dropFirst($0.count) } ?? Substring(self)
        return String(body.drop(while: { $0 == "/" }))
    }
}
