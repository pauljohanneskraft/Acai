import AcaiGit
import AcaiTestSupport
import Foundation
import Testing
@testable import AcaiApp

@Suite("NewCodebaseSheetModel")
@MainActor
struct NewCodebaseSheetModelTests {
    private let remoteURL = URL(string: "https://example.com/team/widgets.git")!
    private let otherRemoteURL = URL(string: "https://example.com/team/gadgets.git")!
    private let fixtureRepositoryURL = URL(string: "https://github.com/octocat/fixture-repo.git")!
    private let mainBranch = GitCheckout.Ref(name: "main", kind: .branch)
    private let developBranch = GitCheckout.Ref(name: "develop", kind: .branch)
    private let releaseTag = GitCheckout.Ref(name: "v1", kind: .tag)

    @MainActor
    private struct Fixture {
        let store: ProjectStore
        let service: FakeGitRemoteService
        let hosting: FixtureGitHubHostingService
        let sheet: NewCodebaseSheetModel

        func tearDown() {
            try? FileManager.default.removeItem(at: store.baseDir)
        }
    }

    private func makeFixture(repositorySizeKilobytes: Int = 1) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("acai-new-codebase-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = ProjectStore(baseDir: root)
        let service = FakeGitRemoteService()
        let hosting = FixtureGitHubHostingService(repositorySizeKilobytes: repositorySizeKilobytes)
        let editor = ProjectCodebaseEditor(
            store: store, persist: {}, notify: {}, invalidateAnalysis: { _ in }, remoteService: service)
        let projectID = editor.addProject(title: "Demo", subtitle: "")
        let sheet = NewCodebaseSheetModel(
            projectID: projectID, editor: editor, hubStoreDirectory: store.gitRepositoriesDir,
            remoteService: service, hostingService: hosting, sizePolicy: CloneSizePolicy(thresholdKilobytes: 100),
            listingDebounce: .zero)
        return Fixture(store: store, service: service, hosting: hosting, sheet: sheet)
    }

    private var account: GitHubTokenStore.StoredAccount {
        GitHubTokenStore.StoredAccount(credential: .personalAccessToken("t"), login: "octocat")
    }

    @Test func remoteAddressListsBranchesAndSelectsTheDefault() async throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }
        let sheet = fixture.sheet
        fixture.service.listings.value[remoteURL] = GitRemoteListing.Result(
            refs: [releaseTag, developBranch, mainBranch], defaultBranch: "main")

        sheet.source = .remoteURL
        sheet.remoteAddress = remoteURL.absoluteString
        await sheet.pendingListing?.value

        #expect(sheet.remoteListing == .loaded([releaseTag, developBranch, mainBranch]))
        #expect(sheet.selectedRemoteRef == mainBranch)
        let pending = try #require(sheet.pendingClone)
        #expect(pending.name == "widgets")
        #expect(pending.remoteURL == remoteURL)
        #expect(pending.ref == mainBranch)
        #expect(pending.sizeKilobytes == nil)
    }

    @Test func aListingForAnOlderAddressIsDiscarded() async throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }
        let sheet = fixture.sheet
        fixture.service.listings.value[remoteURL] = GitRemoteListing.Result(refs: [mainBranch], defaultBranch: "main")
        fixture.service.listings.value[otherRemoteURL] = GitRemoteListing.Result(
            refs: [developBranch], defaultBranch: "develop")
        let gate = AsyncGate()
        fixture.service.listingGate.value = gate

        sheet.source = .remoteURL
        let olderEntered = AsyncGate()
        fixture.service.listingEntered.value = olderEntered
        sheet.remoteAddress = remoteURL.absoluteString
        let olderListing = sheet.pendingListing
        await olderEntered.wait()
        let newerEntered = AsyncGate()
        fixture.service.listingEntered.value = newerEntered
        sheet.remoteAddress = otherRemoteURL.absoluteString
        await newerEntered.wait()
        #expect(fixture.service.callCount(of: "listRemote") == 2)
        await gate.open()
        await olderListing?.value
        await sheet.pendingListing?.value

        #expect(sheet.remoteListing == .loaded([developBranch]))
        #expect(sheet.selectedRemoteRef == developBranch)
        #expect(sheet.pendingClone?.remoteURL == otherRemoteURL)
    }

    @Test func invalidAddressNeverContactsTheRemote() async throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }
        let sheet = fixture.sheet
        sheet.source = .remoteURL

        sheet.remoteAddress = "not a remote"
        #expect(sheet.remoteListing == .invalid(.malformed))
        sheet.remoteAddress = "https://user:secret@example.com/team/widgets.git"
        #expect(sheet.remoteListing == .invalid(.containsCredentials))
        sheet.remoteAddress = "git@example.com:team/widgets.git"
        #expect(sheet.remoteListing == .invalid(.unsupportedScheme))
        await sheet.pendingListing?.value

        #expect(fixture.service.callCount(of: "listRemote") == 0)
        #expect(sheet.pendingClone == nil)
        sheet.remoteAddress = ""
        #expect(sheet.remoteListing == .idle)
    }

    @Test func aLargeRepositoryAsksBeforeCloning() async throws {
        let fixture = try makeFixture(repositorySizeKilobytes: 1_000)
        defer { fixture.tearDown() }
        let sheet = fixture.sheet
        let pending = try await gitHubPendingClone(in: fixture)
        #expect(pending.sizeKilobytes == 1_000)

        let added = await sheet.requestClone(pending)

        #expect(!added)
        #expect(sheet.pendingLargeClone == pending)
        #expect(fixture.service.callCount(of: "attachWorktree") == 0)

        await sheet.clone(pending, depth: .latestSnapshot)

        #expect(sheet.clonePhase == .loaded)
        #expect(fixture.service.calls.value.contains { $0.hasPrefix("attachWorktree main latestSnapshot") })
        #expect(fixture.store.projects.first?.codebases.map(\.name) == ["fixture-repo"])
    }

    @Test func addingToAnAlreadyClonedRepositoryNeverAsks() async throws {
        let fixture = try makeFixture(repositorySizeKilobytes: 1_000)
        defer { fixture.tearDown() }
        let sheet = fixture.sheet
        let gitHubURL = fixtureRepositoryURL
        fixture.service.inspections.value[gitHubURL] = CloneInspection(
            isCloned: true, isShallow: false, lastFetchedAt: nil, worktreeNames: ["codebase-1"])
        let pending = try await gitHubPendingClone(in: fixture)
        await sheet.pendingCloneCheck?.value
        #expect(sheet.isAlreadyCloned(pending.remoteURL))

        let added = await sheet.requestClone(pending)

        #expect(added)
        #expect(sheet.pendingLargeClone == nil)
        #expect(fixture.service.calls.value.contains { $0.hasPrefix("attachWorktree main full") })
    }

    @Test func aGitHubCloneNeedsAnAccountARepositoryAndARef() async throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }
        let sheet = fixture.sheet
        fixture.service.listings.value[fixtureRepositoryURL] = GitRemoteListing.Result(
            refs: [developBranch, mainBranch], defaultBranch: "main")
        sheet.source = .gitHub
        #expect(sheet.pendingClone == nil)

        sheet.account = account
        await sheet.loadRepositories()
        #expect(sheet.repositories == [fixture.hosting.repository])
        #expect(sheet.pendingClone == nil)

        sheet.selectedRepository = fixture.hosting.repository
        await sheet.pendingRefs?.value
        #expect(sheet.selectedRef == mainBranch)
        let pending = try #require(sheet.pendingClone)
        #expect(pending.name == "fixture-repo")
        #expect(pending.remoteURL == fixtureRepositoryURL)

        sheet.selectedRef = nil
        #expect(sheet.pendingClone == nil)
        sheet.selectedRef = mainBranch
        sheet.account = nil
        #expect(sheet.pendingClone == nil)
    }

    private func gitHubPendingClone(in fixture: Fixture) async throws -> PendingClone {
        let sheet = fixture.sheet
        let repository = fixture.hosting.repository
        let gitHubURL = fixtureRepositoryURL
        fixture.service.listings.value[gitHubURL] = GitRemoteListing.Result(
            refs: [developBranch, mainBranch], defaultBranch: repository.defaultBranch)
        sheet.source = .gitHub
        sheet.account = account
        await sheet.loadRepositories()
        sheet.selectedRepository = repository
        await sheet.pendingRefs?.value
        return try #require(sheet.pendingClone)
    }
}
