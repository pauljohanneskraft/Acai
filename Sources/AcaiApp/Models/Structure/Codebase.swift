import Foundation

struct Codebase: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var directoryPath: String
    /// What re-establishes access to `directoryPath` after relaunch under the sandbox. `nil` for an
    /// app-managed directory (see `managedCheckout`) and for codebases added before this field
    /// existed — those fall back to the plain path, which the sandbox may refuse.
    var securityScopedBookmark: SecurityScopedBookmark?
    /// Set when the app cloned this codebase's folder itself. `directoryPath` is then an
    /// app-managed worktree, `securityScopedBookmark` stays `nil`, and `repository` names the remote.
    var managedCheckout: ManagedCheckout?
    var hasArtifact: Bool = false
    var lastIndexed: Date?
    /// `nil` for a codebase indexed before this field existed, or one whose fingerprint couldn't be
    /// computed.
    var indexedFingerprint: CodeStateFingerprint?
    var hasParseErrors: Bool = false
    var parseDiagnosticCount: Int = 0
    var qualityCheck: QualityCheckConfiguration?
    /// Applied at indexing time; `nil` means unfiltered.
    var fileFilter: FileFilter?
    /// The remote this codebase's content comes from: the one the app cloned for a
    /// `managedCheckout`, or the `origin` a picked local folder turned out to track.
    var repository: CodebaseRepositoryReference?
    /// `nil` until a first index offers the route, so codebases indexed before it existed are never offered one.
    var guidedRoute: GuidedRouteOffer?
    /// A revision a local folder is analysed at, read from its repository's history without touching
    /// the checkout. `nil` means the working tree. Never set for a `managedCheckout`, whose revision
    /// is `repository.ref`.
    var analysedRevision: String?

    /// The revision the analysis reflects when it isn't the working tree.
    var pinnedRevision: String? {
        managedCheckout == nil ? analysedRevision : nil
    }
}

extension Codebase {
    private enum CodingKeys: String, CodingKey {
        case id, name, directoryPath, securityScopedBookmark, managedCheckout, hasArtifact, lastIndexed
        case indexedFingerprint, hasParseErrors, parseDiagnosticCount, qualityCheck, fileFilter, repository
        case guidedRoute, analysedRevision
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case githubSource
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        directoryPath = try container.decode(String.self, forKey: .directoryPath)
        securityScopedBookmark = try container.decodeIfPresent(
            SecurityScopedBookmark.self, forKey: .securityScopedBookmark)
        managedCheckout = try container.decodeIfPresent(ManagedCheckout.self, forKey: .managedCheckout)
        hasArtifact = try container.decodeIfPresent(Bool.self, forKey: .hasArtifact) ?? false
        lastIndexed = try container.decodeIfPresent(Date.self, forKey: .lastIndexed)
        indexedFingerprint = try container.decodeIfPresent(CodeStateFingerprint.self, forKey: .indexedFingerprint)
        hasParseErrors = try container.decodeIfPresent(Bool.self, forKey: .hasParseErrors) ?? false
        parseDiagnosticCount = try container.decodeIfPresent(Int.self, forKey: .parseDiagnosticCount) ?? 0
        qualityCheck = try container.decodeIfPresent(QualityCheckConfiguration.self, forKey: .qualityCheck)
        fileFilter = try container.decodeIfPresent(FileFilter.self, forKey: .fileFilter)
        repository = try container.decodeIfPresent(CodebaseRepositoryReference.self, forKey: .repository)
        guidedRoute = try container.decodeIfPresent(GuidedRouteOffer.self, forKey: .guidedRoute)
        analysedRevision = try container.decodeIfPresent(String.self, forKey: .analysedRevision)

        // Without a `repository` it had its own per-codebase clone, which `ProjectStore` discards.
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        if managedCheckout == nil,
           let source = try? legacy.decodeIfPresent(LegacyGitHubSource.self, forKey: .githubSource) {
            managedCheckout = source.managedCheckout
        }
    }
}

enum GuidedRouteOffer: String, Codable, Hashable {
    case offered
    case dismissed
}
