import Foundation
import SwiftUI

/// Resolves a UI-test fixture's base directory from the process environment, so `ProjectStore` can
/// be pointed at deterministic, disposable state instead of the real user's Application
/// Support/Documents directory. Fully inert (`resolveBaseDir()` returns `nil`) unless
/// `ACAI_UITEST_FIXTURE_BASE_DIR` is actually present — a real user's launch never carries it.
///
/// **Environment, not launch arguments.** A launch argument that isn't part of a `-key value` pair
/// is read as a file to open, and an app launched to open files gets no automatic untitled window —
/// measured directly: launching this app with one stray bare token yields zero windows, the same
/// launch without it yields one. The repeatable multi-field values here can't be expressed as a
/// single `-key value` pair, so nothing goes through argv at all rather than relying on every
/// future call site getting the pairing right.
///
/// The values themselves are staged by the test process, not this one: `App/AcaiUITests` (a separate
/// Xcode-project target — no shared internal API) copies its bundled `Fixtures/<name>` resource to a
/// fresh temporary directory before launch and passes that directory's absolute path here (see
/// `XCUIApplication.launchWithFixture(_:)` in `App/AcaiUITests/Support/Launch.swift`). **The
/// variable names below and the ones in `Launch.swift` must match** — they can't share a constant
/// across the SwiftPM package / Xcode-project boundary.
struct UITestFixtureResolver {
    static let fixtureBaseDirVariable = "ACAI_UITEST_FIXTURE_BASE_DIR"

    private let environment: [String: String]

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    func resolveBaseDir() -> URL? {
        url(Self.fixtureBaseDirVariable)
    }

    static let gitHubRemoteVariable = "ACAI_UITEST_GITHUB_REMOTE_URL"

    /// A local git repository to clone/fetch from instead of real github.com.
    func resolveGitHubRemoteURL() -> URL? {
        url(Self.gitHubRemoteVariable)
    }

    static let gitHubFastFixtureRootVariable = "ACAI_UITEST_GITHUB_FAST_FIXTURE_ROOT"

    /// Selects `FastFixtureGitHubRepositoryService` over the real-git `FixtureGitHubRepositoryService`.
    func resolveGitHubFastFixtureRoot() -> URL? {
        url(Self.gitHubFastFixtureRootVariable)
    }

    static let codebaseArtifactsVariable = "ACAI_UITEST_CODEBASE_ARTIFACTS"

    /// Newline-separated `<codebaseID>\t<path>` records — see `CodebaseAnalyzingResolver`. A
    /// codebase with no entry still gets the real analyzer. Tab and newline are the separators
    /// because a path may legally contain anything else.
    func resolveCodebaseArtifactURLs() -> [UUID: URL] {
        var result: [UUID: URL] = [:]
        for fields in records(Self.codebaseArtifactsVariable, fieldCount: 2) {
            guard let codebaseID = UUID(uuidString: fields[0]) else { continue }
            result[codebaseID] = URL(fileURLWithPath: fields[1])
        }
        return result
    }

    static let comparisonArtifactsVariable = "ACAI_UITEST_COMPARISON_ARTIFACTS"

    struct ComparisonArtifactKey: Hashable {
        let codebaseID: UUID
        let ref: String
    }

    /// Newline-separated `<codebaseID>\t<ref>\t<path>` records — see `ComparisonArtifactResolver`.
    /// A `(codebaseID, ref)` pair with no entry still gets a real `GitRevisionSnapshot`.
    func resolveComparisonArtifactURLs() -> [ComparisonArtifactKey: URL] {
        var result: [ComparisonArtifactKey: URL] = [:]
        for fields in records(Self.comparisonArtifactsVariable, fieldCount: 3) {
            guard let codebaseID = UUID(uuidString: fields[0]) else { continue }
            result[.init(codebaseID: codebaseID, ref: fields[1])] = URL(fileURLWithPath: fields[2])
        }
        return result
    }

    static let colorSchemeVariable = "ACAI_UITEST_COLOR_SCHEME"

    /// A forced `light`/`dark` appearance, so snapshot-test screenshots are deterministic regardless
    /// of the runner's or developer's own system appearance default (an unpinned mismatch flips
    /// nearly every pixel, not just the few percent of AA/font-hinting noise this suite tolerates).
    func resolveColorScheme() -> ColorScheme? {
        switch environment[Self.colorSchemeVariable] {
        case "dark":
            return .dark
        case "light":
            return .light
        default:
            return nil
        }
    }

    private func url(_ variable: String) -> URL? {
        guard let path = environment[variable], !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// Records with the wrong field count are dropped rather than partially applied — a malformed
    /// entry should leave the real implementation in place, not a half-built fixture.
    private func records(_ variable: String, fieldCount: Int) -> [[String]] {
        guard let value = environment[variable], !value.isEmpty else { return [] }
        return value.split(separator: "\n")
            .map { record in
                record
                    .split(separator: "\t", maxSplits: fieldCount - 1, omittingEmptySubsequences: false)
                    .map(String.init)
            }
            .filter { $0.count == fieldCount }
    }
}
