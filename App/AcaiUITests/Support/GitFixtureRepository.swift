import Foundation
import SwiftGitX

/// Builds real git history inside a fixture directory at UI-test launch time, via `SwiftGitX`
/// itself rather than shelling out to `/usr/bin/git`. That's not a style choice: `Process`/`Pipe`
/// don't exist at all in iOS's Foundation (a real, compile-time platform constraint discovered
/// while building this — `Tests/AcaiGitTests/GitFixture.swift`'s SwiftPM-side counterpart can only
/// get away with `Process` because that target is macOS-only by construction, whereas this one is
/// compiled into `Acai-iOSUITests` too), so building the fixture with the same library the app
/// itself uses is both the only option and the more faithful one.
struct GitFixtureRepository {
    let directory: URL

    /// Turns `directory` (an already-staged, non-git fixture directory) into a real git repo whose
    /// current history is exactly `paths`' present-on-disk content — deliberately leaving the
    /// directory free for the caller to make a further, uncommitted edit afterward, so comparing
    /// the working tree against `HEAD` later produces a real, visible delta rather than a vacuous
    /// "compared identical states" no-op. See `CompareGitRevisionTests`.
    func commitInitialRevision(paths: [String]) throws {
        let repository = try Repository.create(at: directory)
        try configureIdentity(repository)
        try repository.add(paths: paths)
        try repository.commit(message: "initial")
        try ensureInitialBranchIsNamedMain(repository)
    }

    /// Builds a standalone repository from scratch, standing in for a GitHub remote
    /// (`GitHubAddCodebaseTests`): a minimal Swift package on `main` with two commits (adding
    /// `Widget.swift` then `Gadget.swift`), and a `feature` branch one commit further ahead (adding
    /// `Extra.swift`) — so cloning `main` then switching to `feature` produces a visibly different
    /// Class Diagram, proving the switch actually re-fetched/re-checked-out real content rather
    /// than being a no-op.
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

    /// `git_commit_create_from_stage` needs `user.name`/`user.email` from *some* config scope, and
    /// the UI test process has no reliable global `~/.gitconfig` to fall back on (confirmed
    /// empirically: committing without this failed with "config value 'user.name' was not found")
    /// — so this fixture always sets its own repo-local identity rather than depending on one.
    private func configureIdentity(_ repository: Repository) throws {
        try repository.config.set("user.name", to: "UI Test")
        try repository.config.set("user.email", to: "uitest@example.com")
    }

    /// Renames the just-created repository's initial branch (whatever libgit2 defaulted it to —
    /// "master" unless the host's global git config sets `init.defaultBranch`) to "main", so this
    /// fixture's branch name is deterministic regardless of the host machine's config. Must run
    /// right after the first commit: an unborn HEAD (no commits yet) has no branch to rename.
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
