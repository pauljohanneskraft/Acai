import Foundation

public struct AcaiConstants: Sendable {
    public static let standard = AcaiConstants()

    /// Ceiling, in bytes, on a source file the analyzer will read. A larger file is skipped and
    /// recorded as a `.skipped` ``ParseDiagnostic`` carrying its size, so it shows up in the health
    /// report rather than silently costing memory and parse time.
    ///
    /// The default is generous — an ordinary hand-written source file is orders of magnitude
    /// smaller — and exists to bound the pathological case: a bundled `.js`, a vendored single-file
    /// library or a generated file that escaped every exclusion, read whole into a `String`.
    public let maximumSourceFileBytes: Int

    public init(maximumSourceFileBytes: Int = 2 * 1024 * 1024) {
        self.maximumSourceFileBytes = maximumSourceFileBytes
    }

    private var baseDirectory: URL {
        #if os(macOS)
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".acai")
        #else
        (try? FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory.appendingPathComponent("acai", isDirectory: true)
        #endif
    }

    public var analysisDirectory: URL {
        baseDirectory.appendingPathComponent("analysis")
    }

    /// Directories skipped while collecting sources regardless of language. Only the universal
    /// version-control directory lives here; each language's build-output/dependency directories
    /// (`node_modules`, `Pods`, `target`, …) come from its `LanguageConfiguration.excludedDirectories`
    /// and are unioned in by the composition root.
    public let defaultExcludedSourceDirectories: Set<String> = [".git"]

    /// Schema/tool version stamped into every analyzed `CodeArtifact`'s metadata. Bump when the
    /// stored `CodeArtifact` JSON shape changes in a way consumers need to detect.
    public let toolVersion = "1.0.0"
}
