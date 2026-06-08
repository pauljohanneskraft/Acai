// MARK: - Build Product Resolution

/// Derives the *compiled product* (build target / module) a source file belongs to,
/// purely from its relative file path — no build-manifest parsing.
///
/// The result is used to partition a diagram into one "package" box per product:
/// types are grouped by product, laid out within each, then the products are laid out
/// relative to one another.
///
/// Granularity is the build **module/target**, recognised from well-known layout markers:
/// - Swift Package Manager: `Sources/<Target>/…`, `Tests/<Target>/…`  → `<Target>`
/// - Gradle / Maven:        `…/<Module>/src/{main,test}/…`            → `<Module>`
/// - JS/TS monorepo:        `packages/<Package>/…`                    → `<Package>`
/// - Anything else:         the first directory component, else `"root"`
///
/// Single-module projects and paths without a recognisable marker collapse to a single
/// group (often `"root"`), which still renders as one package box.
public enum BuildProduct {

    /// The group name used when a file path carries no usable directory information.
    public static let fallbackGroup = "root"

    /// Returns the product/module name for a relative source-file path.
    public static func productName(forFilePath filePath: String) -> String {
        // Directory components only (drop the trailing file name), ignoring any
        // leading slash or `./` so absolute and relative paths behave the same.
        let parts =
            filePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { $0 != "." }
        guard parts.count > 1 else { return fallbackGroup }
        let dirs = Array(parts.dropLast())

        // SwiftPM: the component directly after `Sources` / `Tests` is the target.
        for marker in ["Sources", "Tests"] {
            if let idx = dirs.firstIndex(of: marker), idx + 1 < dirs.count {
                return dirs[idx + 1]
            }
        }

        // JS/TS monorepo: the component directly after `packages` is the package.
        if let idx = dirs.firstIndex(of: "packages"), idx + 1 < dirs.count {
            return dirs[idx + 1]
        }

        // Gradle / Maven: the module directory is the component just before `src`.
        // When `src` is the first component there is no module prefix (single module).
        if let idx = dirs.firstIndex(of: "src") {
            return idx > 0 ? dirs[idx - 1] : fallbackGroup
        }

        // Fallback: the top-level directory.
        return dirs.first ?? fallbackGroup
    }
}
