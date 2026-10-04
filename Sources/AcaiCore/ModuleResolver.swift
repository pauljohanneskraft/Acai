// MARK: - Module Resolution

/// Derives the *compiled product* (build target / module) a source file belongs to, purely from
/// its relative file path — no build-manifest parsing.
///
/// The result is used to partition a diagram into one "package" box per product: types are grouped
/// by product, laid out within each, then the products are laid out relative to one another.
///
/// The matching is driven entirely by the configured ``anchors`` (data), so the algorithm names no
/// build system itself — `.standard` supplies the well-known layout conventions. Single-module
/// projects and paths without a recognisable anchor collapse to a single group (``fallbackGroup``),
/// which still renders as one package box.
///
/// A folder holding several projects needs more than the anchor: two projects each with a `Core`
/// target derive the same name from their paths. ``productName(forFilePath:inRoot:)`` qualifies the
/// anchor-derived name with the project root the file was discovered under; ``ModuleMap`` decides
/// per artifact when that is needed.
public struct ModuleResolver: Sendable {

    /// A directory name that locates the module within a path: the module is the directory
    /// component immediately `before` or `after` the anchor.
    public struct Anchor: Sendable {
        public enum Position: Sendable {
            /// e.g. SwiftPM `Sources/<Target>`.
            case after
            /// e.g. Gradle `<Module>/src`.
            case before
        }

        public let directory: String
        public let position: Position

        public init(_ directory: String, _ position: Position) {
            self.directory = directory
            self.position = position
        }
    }

    /// What the anchor scan found, kept separate from the name it produces because the three
    /// outcomes fall back differently: a qualified name drops to its root's name where an
    /// unqualified one drops to the leading directory.
    private enum AnchorMatch {
        /// An anchor located the module's directory component.
        case module(String)
        /// An anchor matched, but it sits at the path's head — a single-module layout with no
        /// module component to name.
        case single
        /// No anchor appears in the path.
        case none
    }

    /// Anchors tried in priority order; the first that matches wins.
    public let anchors: [Anchor]

    public let fallbackGroup: String

    public init(anchors: [Anchor], fallbackGroup: String = "root") {
        self.anchors = anchors
        self.fallbackGroup = fallbackGroup
    }

    /// The well-known layout conventions: SwiftPM (`Sources/Tests/<Target>`), JS/TS monorepo
    /// (`packages/<Package>`), Gradle/Maven (`<Module>/src`).
    public static let standard = ModuleResolver(anchors: [
        Anchor("Sources", .after),
        Anchor("Tests", .after),
        Anchor("packages", .after),
        Anchor("src", .before)
    ])

    public func productName(forFilePath filePath: String) -> String {
        let dirs = directories(of: filePath)
        guard !dirs.isEmpty else { return fallbackGroup }

        switch match(in: dirs) {
        case .module(let name):
            return name
        case .single:
            return fallbackGroup
        case .none:
            return dirs.first ?? fallbackGroup
        }
    }

    /// The module name qualified by the project root `filePath` was discovered under, as
    /// `<root name>/<anchor-derived name>`. A file whose root holds no anchor is the root itself,
    /// so every file of a single-module project shares one name.
    ///
    /// `root` is relative to the analysed folder, as `CodeArtifact.DiscoveredRoot/path` records it;
    /// `"."` (the analysed folder itself) is named ``fallbackGroup``, since the folder has no name
    /// of its own in a relative path.
    public func productName(forFilePath filePath: String, inRoot root: String) -> String {
        let rootComponents = root.pathComponentsIgnoringDots
        let name = rootComponents.last ?? fallbackGroup
        let fileComponents = filePath.pathComponentsIgnoringDots
        let relative =
            fileComponents.starts(with: rootComponents)
            ? Array(fileComponents.dropFirst(rootComponents.count))
            : fileComponents

        guard case .module(let module) = match(in: Array(relative.dropLast())) else { return name }
        return "\(name)/\(module)"
    }

    // MARK: - Helpers

    private func match(in dirs: [String]) -> AnchorMatch {
        for anchor in anchors {
            guard let index = dirs.firstIndex(of: anchor.directory) else { continue }
            switch anchor.position {
            case .after:
                if index + 1 < dirs.count { return .module(dirs[index + 1]) }
            case .before:
                return index > 0 ? .module(dirs[index - 1]) : .single
            }
        }
        return .none
    }

    private func directories(of filePath: String) -> [String] {
        let parts = filePath.pathComponentsIgnoringDots
        guard parts.count > 1 else { return [] }
        return Array(parts.dropLast())
    }
}

extension ModuleResolver {
    /// How a root path is named as a project: its last component, or ``fallbackGroup`` for `"."`
    /// (the analysed folder itself), which has no name of its own in a relative path.
    public func projectName(ofRoot root: String) -> String {
        root.pathComponentsIgnoringDots.last ?? fallbackGroup
    }
}

extension String {
    /// The path's components with `.` and empty segments dropped, so a leading `./` or `/` never
    /// shifts the anchor scan.
    public var pathComponentsIgnoringDots: [String] {
        split(separator: "/", omittingEmptySubsequences: true).map(String.init).filter { $0 != "." }
    }
}
