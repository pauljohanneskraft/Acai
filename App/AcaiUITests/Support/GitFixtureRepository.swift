import Foundation
import SwiftGitX

/// Builds real git history via `SwiftGitX` rather than shelling out to `/usr/bin/git`: `Process`/
/// `Pipe` don't exist at all in iOS's Foundation, and this fixture is compiled into
/// `Acai-iOSUITests` too (unlike `Tests/AcaiGitTests/GitFixture.swift`'s macOS-only counterpart).
struct GitFixtureRepository {
    let directory: URL

    /// Turns `directory` (an already-staged, non-git fixture directory) into a real git repo whose
    /// current history is exactly `paths`' present-on-disk content — deliberately leaves the
    /// directory free for the caller to make a further, uncommitted edit afterward, so comparing
    /// the working tree against `HEAD` later produces a real delta. See `CompareGitRevisionTests`.
    func commitInitialRevision(paths: [String]) throws {
        let repository = try Repository.create(at: directory)
        try configureIdentity(repository)
        try repository.add(paths: paths)
        try repository.commit(message: "initial")
        try ensureInitialBranchIsNamedMain(repository)
    }

    /// Standalone repository standing in for a GitHub remote (`GitHubAddCodebaseTests`): `main`
    /// with two commits, and a `feature` branch one commit further ahead — so cloning `main` then
    /// switching to `feature` produces a visibly different Class Diagram, proving the switch
    /// actually re-fetched/re-checked-out real content rather than being a no-op.
    func makeRemote() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try write(packageManifest, to: "Package.swift")
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("Sources/FixtureRepo"), withIntermediateDirectories: true)

        let repository = try Repository.create(at: directory)
        try configureIdentity(repository)

        try write("public class Widget {}\n", to: "Sources/FixtureRepo/Widget.swift")
        try repository.add(paths: ["Package.swift", "Sources/FixtureRepo/Widget.swift"])
        try repository.commit(message: "add Widget")
        try ensureInitialBranchIsNamedMain(repository)

        try write("public class Gadget {}\n", to: "Sources/FixtureRepo/Gadget.swift")
        try repository.add(path: "Sources/FixtureRepo/Gadget.swift")
        let mainTip = try repository.commit(message: "add Gadget")

        let feature = try repository.branch.create(named: "feature", target: mainTip)
        try repository.switch(to: feature)
        try write("public class Extra {}\n", to: "Sources/FixtureRepo/Extra.swift")
        try repository.add(path: "Sources/FixtureRepo/Extra.swift")
        try repository.commit(message: "add Extra")

        try repository.switch(to: repository.branch["main", type: .local]!)
    }

    /// No real git history — one plain directory per ref, matching what
    /// `FastFixtureGitHubRepositoryService` expects. Use instead of `makeRemote()` when a journey
    /// doesn't need to prove real git mechanics. `refs`: ref name → relative file path → content.
    func makeCannedRemote(refs: [String: [String: String]]) throws {
        for (ref, files) in refs {
            let refDirectory = directory.appendingPathComponent(ref, isDirectory: true)
            try FileManager.default.createDirectory(at: refDirectory, withIntermediateDirectories: true)
            for (relativePath, content) in files {
                let fileURL = refDirectory.appendingPathComponent(relativePath)
                try FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try content.write(to: fileURL, atomically: true, encoding: .utf8)
            }
        }
    }

    /// The UI test process has no reliable global `~/.gitconfig` to fall back on (confirmed
    /// empirically: committing without this failed with "config value 'user.name' was not found").
    private func configureIdentity(_ repository: Repository) throws {
        try repository.config.set("user.name", to: "UI Test")
        try repository.config.set("user.email", to: "uitest@example.com")
    }

    /// Makes this fixture's branch name deterministic regardless of the host's `init.defaultBranch`
    /// config. Must run right after the first commit: an unborn HEAD has no branch to rename.
    private func ensureInitialBranchIsNamedMain(_ repository: Repository) throws {
        guard let branch = try repository.HEAD as? Branch, branch.name != "main" else { return }
        try repository.branch.rename(branch, to: "main")
    }

    private var packageManifest: String {
        """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "FixtureRepo",
            targets: [
                .target(name: "FixtureRepo")
            ]
        )

        """
    }

    private func write(_ content: String, to relativePath: String) throws {
        try content.write(
            to: directory.appendingPathComponent(relativePath), atomically: true, encoding: .utf8)
    }
}
