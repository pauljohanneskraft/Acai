import AcaiCore
import Foundation
import Testing
@testable import AcaiApp

@Suite("Adding a folder that holds several projects", .timeLimit(.minutes(1)))
@MainActor
struct MultiRootCodebaseTests {
    private struct StubRootDiscovery: ProjectRootDiscovering {
        let roots: [CodeArtifact.DiscoveredRoot]

        func discoverRoots(in directory: URL) -> [CodeArtifact.DiscoveredRoot] { roots }
    }

    @MainActor
    private struct Fixture {
        let base: URL
        let store: ProjectStore
        let projectID: UUID
        let sheet: NewCodebaseSheetModel
        let folder: URL

        var codebases: [Codebase] {
            store.projects.first { $0.id == projectID }?.codebases ?? []
        }

        func tearDown() {
            try? FileManager.default.removeItem(at: base)
        }
    }

    private func root(
        _ path: String, detector: String = "SwiftPackageDetector", languages: [String] = ["swift"],
        isFallback: Bool = false
    ) -> CodeArtifact.DiscoveredRoot {
        CodeArtifact.DiscoveredRoot(
            path: path, detector: detector,
            languages: languages.map { CodeArtifact.SourceLanguage(rawValue: $0) }, isFallback: isFallback)
    }

    /// `subfolders` are created for real: splitting mints a bookmark per child inside an access scope
    /// on the parent, which probes that each one is a listable directory.
    private func makeFixture(
        discovering roots: [CodeArtifact.DiscoveredRoot], subfolders: [String] = []
    ) throws -> Fixture {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("acai-multi-root-\(UUID().uuidString)", isDirectory: true)
        let folder = base.appendingPathComponent("Workspace", isDirectory: true)
        let storeDir = base.appendingPathComponent("store", isDirectory: true)
        for directory in [folder, storeDir] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        for subfolder in subfolders {
            try FileManager.default.createDirectory(
                at: folder.appendingPathComponent(subfolder, isDirectory: true), withIntermediateDirectories: true)
        }
        let store = ProjectStore(baseDir: storeDir)
        let editor = ProjectCodebaseEditor(store: store, persist: {}, notify: {}, invalidateAnalysis: { _ in })
        let projectID = editor.addProject(title: "Demo", subtitle: "")
        let sheet = NewCodebaseSheetModel(
            projectID: projectID, editor: editor, hubStoreDirectory: store.gitRepositoriesDir,
            remoteService: FakeGitRemoteService(), hostingService: FixtureGitHubHostingService(),
            listingDebounce: .zero, rootDiscovery: StubRootDiscovery(roots: roots))
        return Fixture(base: base, store: store, projectID: projectID, sheet: sheet, folder: folder)
    }

    // MARK: - The plan

    @Test func oneRootOffersNoChoice() {
        let plan = MultiRootPlan(roots: [root(".")], checkedPaths: ["."])
        #expect(!plan.isOffered)
    }

    @Test func checkingAndUncheckingTracksEachRootByPath() {
        var plan = MultiRootPlan(roots: [root("App"), root("Core")], checkedPaths: ["App", "Core"])
        #expect(plan.isOffered)
        plan.setChecked(false, for: root("App"))
        #expect(!plan.isChecked(root("App")))
        #expect(plan.isChecked(root("Core")))
        #expect(plan.checkedRoots.map(\.path) == ["Core"])
    }

    @Test func splittingNeedsAtLeastOneCheckedRootButCombiningDoesNot() {
        var plan = MultiRootPlan(roots: [root("App"), root("Core")], checkedPaths: [])
        #expect(!plan.isSatisfiable)
        plan.combinesIntoOne = true
        #expect(plan.isSatisfiable)
    }

    @Test func theFolderItselfIsNeverResolvedAsASiblingDotDirectory() {
        let parent = URL(fileURLWithPath: "/tmp/Workspace", isDirectory: true)
        let plan = MultiRootPlan(roots: [root("."), root("Core")], checkedPaths: [".", "Core"])
        #expect(plan.folders(under: parent).map(\.lastPathComponent) == ["Workspace", "Core"])
    }

    // MARK: - Discovery

    @Test func discoveryChecksEveryRootItFinds() async throws {
        let fixture = try makeFixture(discovering: [root("App"), root("Core")])
        defer { fixture.tearDown() }
        let sheet = fixture.sheet

        sheet.directoryURL = fixture.folder
        sheet.discoverRoots()
        #expect(sheet.discoveryPhase.isInFlight)
        await sheet.pendingDiscovery?.value

        #expect(sheet.discoveryPhase == .loaded)
        #expect(sheet.plan.roots.map(\.path) == ["App", "Core"])
        #expect(sheet.plan.checkedPaths == ["App", "Core"])
    }

    @Test func pickingAnotherFolderDropsTheFirstFoldersRoots() async throws {
        let fixture = try makeFixture(discovering: [root("App"), root("Core")])
        defer { fixture.tearDown() }
        let sheet = fixture.sheet

        sheet.directoryURL = fixture.folder
        sheet.discoverRoots()
        await sheet.pendingDiscovery?.value
        #expect(sheet.plan.isOffered)

        sheet.directoryURL = nil
        sheet.discoverRoots()
        #expect(sheet.plan.roots.isEmpty)
        #expect(sheet.discoveryPhase == .idle)
    }

    @Test func dismissingWhileDiscoveringAddsNothing() async throws {
        let fixture = try makeFixture(discovering: [root("App"), root("Core")])
        defer { fixture.tearDown() }
        let sheet = fixture.sheet

        sheet.directoryURL = fixture.folder
        sheet.discoverRoots()
        sheet.cancelPendingWork()
        await sheet.pendingDiscovery?.value

        #expect(sheet.plan.roots.isEmpty)
        #expect(fixture.codebases.isEmpty)
    }

    // MARK: - Adding

    @Test func splittingAddsOneCodebasePerCheckedRootNamedAfterItsFolder() async throws {
        let fixture = try makeFixture(
            discovering: [root("App"), root("Core"), root("Tools")], subfolders: ["App", "Core", "Tools"])
        defer { fixture.tearDown() }
        let sheet = fixture.sheet

        sheet.directoryURL = fixture.folder
        sheet.discoverRoots()
        await sheet.pendingDiscovery?.value
        sheet.setRootChecked(false, for: sheet.plan.roots[2])

        #expect(sheet.canAddLocalFolder)
        let created = sheet.addLocalFolder()

        #expect(created.count == 2)
        #expect(fixture.codebases.map(\.name) == ["App", "Core"])
        #expect(fixture.codebases.map(\.id) == created)
        #expect(fixture.codebases.map { URL(fileURLWithPath: $0.directoryPath).lastPathComponent }
            == ["App", "Core"])
    }

    @Test func combiningAddsOneCodebaseForTheWholeFolderNamedAfterIt() async throws {
        let fixture = try makeFixture(discovering: [root("App"), root("Core")], subfolders: ["App", "Core"])
        defer { fixture.tearDown() }
        let sheet = fixture.sheet

        sheet.directoryURL = fixture.folder
        sheet.discoverRoots()
        await sheet.pendingDiscovery?.value
        sheet.plan.combinesIntoOne = true

        let created = sheet.addLocalFolder()

        #expect(created.count == 1)
        #expect(fixture.codebases.map(\.name) == ["Workspace"])
        #expect(fixture.codebases.first?.directoryPath == fixture.folder.path)
    }

    @Test func uncheckingEverythingLeavesNothingToAdd() async throws {
        let fixture = try makeFixture(discovering: [root("App"), root("Core")], subfolders: ["App", "Core"])
        defer { fixture.tearDown() }
        let sheet = fixture.sheet

        sheet.directoryURL = fixture.folder
        sheet.discoverRoots()
        await sheet.pendingDiscovery?.value
        for root in sheet.plan.roots {
            sheet.setRootChecked(false, for: root)
        }

        #expect(!sheet.canAddLocalFolder)
        #expect(sheet.addLocalFolder().isEmpty)
        #expect(fixture.codebases.isEmpty)
    }

    @Test func aSingleRootKeepsTheOriginalOneCodebaseBehaviour() async throws {
        let fixture = try makeFixture(discovering: [root(".")])
        defer { fixture.tearDown() }
        let sheet = fixture.sheet

        sheet.directoryURL = fixture.folder
        sheet.discoverRoots()
        await sheet.pendingDiscovery?.value

        #expect(!sheet.plan.isOffered)
        #expect(sheet.canAddLocalFolder)
        #expect(sheet.addLocalFolder().count == 1)
        #expect(fixture.codebases.map(\.name) == ["Workspace"])
        #expect(fixture.codebases.first?.directoryPath == fixture.folder.path)
    }

    /// Splitting needs a root to make a codebase from; combining makes one from the folder itself,
    /// so it stays addable with every root unchecked.
    @Test func combiningStaysAddableWithEveryRootUnchecked() async throws {
        let fixture = try makeFixture(discovering: [root("App"), root("Core")], subfolders: ["App", "Core"])
        defer { fixture.tearDown() }
        let sheet = fixture.sheet

        sheet.directoryURL = fixture.folder
        sheet.discoverRoots()
        await sheet.pendingDiscovery?.value
        for root in sheet.plan.roots {
            sheet.setRootChecked(false, for: root)
        }
        #expect(!sheet.canAddLocalFolder)

        sheet.plan.combinesIntoOne = true
        #expect(sheet.canAddLocalFolder)
    }

    /// Add waits for the walk, so a folder of several projects cannot be added before it has asked.
    @Test func addingWaitsForTheWalk() async throws {
        let fixture = try makeFixture(discovering: [root("App"), root("Core")], subfolders: ["App", "Core"])
        defer { fixture.tearDown() }
        let sheet = fixture.sheet

        sheet.directoryURL = fixture.folder
        sheet.discoverRoots()
        #expect(sheet.discoveryPhase.isInFlight)
        #expect(!sheet.canAddLocalFolder)

        await sheet.pendingDiscovery?.value
        #expect(sheet.canAddLocalFolder)
    }

    // MARK: - The real walk

    @Test func theRealDiscovererFindsEachPackageBelowTheFolder() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("acai-real-roots-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["Alpha", "Beta"] {
            let sources = folder.appendingPathComponent("\(name)/Sources/\(name)", isDirectory: true)
            try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
            try "// swift-tools-version:6.0\n".write(
                to: folder.appendingPathComponent("\(name)/Package.swift"), atomically: true, encoding: .utf8)
            try "struct \(name) {}\n".write(
                to: sources.appendingPathComponent("\(name).swift"), atomically: true, encoding: .utf8)
        }

        let roots = ProjectRootDiscoverer().discoverRoots(in: folder)

        #expect(roots.count > 1)
        #expect(Set(roots.map(\.path)).isSuperset(of: ["Alpha", "Beta"]))
    }
}
