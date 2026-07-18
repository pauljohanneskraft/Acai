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
public struct ModuleResolver: Sendable {

    /// A directory name that locates the module within a path: the module is the directory
    /// component immediately `before` or `after` the anchor.
    public struct Anchor: Sendable {
        public enum Position: Sendable {
            /// The module is the component just *after* the anchor (e.g. SwiftPM `Sources/<Target>`).
            case after
            /// The module is the component just *before* the anchor (e.g. Gradle `<Module>/src`).
            case before
        }

        public let directory: String
        public let position: Position

        public init(_ directory: String, _ position: Position) {
            self.directory = directory
            self.position = position
        }
    }

    /// Anchors tried in priority order; the first that matches wins.
    public let anchors: [Anchor]

    /// The group name used when a file path carries no usable directory information.
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

    /// Returns the product/module name for a relative source-file path.
    public func productName(forFilePath filePath: String) -> String {
        // Directory components only (drop the trailing file name), ignoring any leading slash or
        // `./` so absolute and relative paths behave the same.
        let parts =
            filePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { $0 != "." }
        guard parts.count > 1 else { return fallbackGroup }
        let dirs = Array(parts.dropLast())

        for anchor in anchors {
            guard let idx = dirs.firstIndex(of: anchor.directory) else { continue }
            switch anchor.position {
            case .after:
                if idx + 1 < dirs.count { return dirs[idx + 1] }
            case .before:
                // When the anchor is the first component there is no module prefix (single module).
                return idx > 0 ? dirs[idx - 1] : fallbackGroup
            }
        }

        // Fallback: the top-level directory.
        return dirs.first ?? fallbackGroup
    }
}
