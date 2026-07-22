import XCTest

/// An anchor purely so `Bundle(for:)` can resolve the UI test bundle — an Xcode-project target has
/// no SwiftPM `Bundle.module`, unlike `Tests/AcaiAppTests`.
private final class FixtureBundleAnchor {}

extension XCUIApplication {
    /// Launches the app pointed at a fresh, disposable copy of the named fixture
    /// (`Fixtures/<name>` in this UI test bundle) instead of the real user's persisted state.
    ///
    /// Fixture JSON may reference its own eventual on-disk location via the literal placeholder
    /// `$FIXTURE_ROOT` (its runtime path isn't known until after this copy, since it lands in a
    /// freshly generated temporary directory) — every occurrence in every file under the copy is
    /// substituted with the real destination path before launch.
    ///
    /// **The launch-argument name here must match `UITestFixtureResolver.launchArgument`**
    /// (`Sources/AcaiApp/UITestSupport.swift`) — the two can't share a constant across the SwiftPM
    /// package / Xcode-project boundary. See `TESTING_ARCHITECTURE.md` Layer 2.
    ///
    /// `configure`, if given, runs after staging (so it can edit the staged fixture in place — e.g.
    /// turn a plain directory into a real git repo, or build a standalone "remote" repo alongside
    /// it) and before `launch()`, so it can also append further `launchArguments` (e.g.
    /// `-AcaiUITestGitHubRemoteURL`) that only make sense once its own setup ran.
    func launchWithFixture(
        _ name: String,
        configure: (XCUIApplication, URL) throws -> Void = { _, _ in },
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let testBundle = Bundle(for: FixtureBundleAnchor.self)
        guard let fixtureURL = testBundle.url(
            forResource: name, withExtension: nil, subdirectory: "Fixtures"
        ) else {
            XCTFail("Missing UI test fixture '\(name)' in the test bundle's Fixtures/ folder", file: file, line: line)
            return
        }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("AcaiUITestFixture-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.copyItem(at: fixtureURL, to: destination)
            try substituteFixtureRoot(in: destination)
            try configure(self, destination)
        } catch {
            XCTFail("Could not stage UI test fixture '\(name)': \(error)", file: file, line: line)
            return
        }

        launchArguments += ["-AcaiUITestFixtureBaseDir", destination.path]
        launch()
    }

    /// Replaces every `$FIXTURE_ROOT` occurrence in every file under `root` with `root`'s own
    /// path, in place.
    private func substituteFixtureRoot(in root: URL) throws {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey]
        ) else { return }
        for case let fileURL as URL in enumerator {
            guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
                  let contents = try? String(contentsOf: fileURL, encoding: .utf8),
                  contents.contains("$FIXTURE_ROOT") else { continue }
            let substituted = contents.replacingOccurrences(of: "$FIXTURE_ROOT", with: root.path)
            try substituted.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }
}
