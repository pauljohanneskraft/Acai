import Foundation
import Testing
import AcaiCore
import AcaiGit
import AcaiQuality
import AcaiTestSupport
@testable import AcaiApp

/// Decodes the app's committed persistence snapshots on every run, through the stores' own load
/// paths rather than a test-local decoder — so an encoder/decoder mismatch (a date strategy, a
/// renamed key, a field that stopped being optional) fails here instead of on a user's install.
///
/// A deliberate format change **adds a new snapshot** (`ACAI_RECORD_LEGACY_CORPUS=1 swift test
/// --filter LegacyCorpusApp`, optionally with `ACAI_LEGACY_CORPUS_LABEL`) and never rewrites an
/// existing one — an old snapshot is the only evidence that yesterday's file still decodes.
@Suite("Legacy corpus decode (AcaiApp)", .timeLimit(.minutes(1)))
@MainActor
struct LegacyCorpusAppDecodeTests {
    private let corpus = LegacyCorpus()
    private let sample = LegacyCorpusAppSample()

    @Test func theCorpusIsNotEmpty() {
        #expect(!corpus.snapshots.isEmpty, "no snapshot under \(corpus.root.path)")
    }

    @Test func everySnapshotLoadsThroughProjectStore() throws {
        for snapshot in corpus.snapshots {
            let label = snapshot.lastPathComponent
            try withCopiedStore(from: snapshot) { store in
                let project = try #require(store.projects.first { $0.id == sample.projectID }, "\(label)")
                #expect(store.projects.count == 1, "\(label)")
                #expect(project.title == "Corpus Project", "\(label)")
                #expect(project.subtitle == "Recorded persistence", "\(label)")
                #expect(project.freeformDiagramIDs == [sample.freeformID], "\(label)")
                #expect(project.generatedDiagramIDs.count == 10, "\(label)")

                try expectCodebase(project.codebases.first, label: label)
                try expectGeneratedDiagrams(store, label: label)
                try expectFreeformDiagram(store, label: label)
                // The pre-shared-store `artifacts/codebase_<id>.json` envelope, read for migration.
                #expect(store.artifact(for: sample.codebaseID)?.types.first?.id == "Corpus.Service", "\(label)")
            }
        }
    }

    @Test func everySnapshotLoadsItsFilterPresetsAndSuppressions() throws {
        for snapshot in corpus.snapshots {
            let label = snapshot.lastPathComponent
            let baseDir = snapshot.appendingPathComponent("store", isDirectory: true)

            let presets = FilterPresetStore(baseDir: baseDir).load(projectID: sample.projectID)
            #expect(presets.formatVersion == 1, "\(label)")
            let preset = try #require(presets.presets.first, "\(label)")
            #expect(preset.id == sample.presetID, "\(label)")
            #expect(preset.name == "Public core only", "\(label)")
            #expect(preset.selector?.minimumAccess == .public, "\(label)")
            #expect(preset.selector?.explicitIDs == ["Corpus.Service"], "\(label)")
            #expect(preset.fileFilter?.rules.map(\.action) == [.block], "\(label)")

            let baseline = FindingsSuppressionStore(baseDir: baseDir).load(projectID: sample.projectID)
            #expect(baseline.formatVersion == 1, "\(label)")
            #expect(
                baseline.suppressedFindingIDs
                    == ["cycle:AcaiCore->AcaiDiagram", "budget:Corpus.Service:members"],
                "\(label)"
            )
        }
    }

    @Test func everySnapshotLoadsItsGitHubAccounts() throws {
        for snapshot in corpus.snapshots {
            let label = snapshot.lastPathComponent

            let app = try #require(
                GitHubTokenStore(fileURL: snapshot.appendingPathComponent("github-token.json")).load(), "\(label)")
            #expect(app.login == "corpus-user", "\(label)")
            #expect(app.avatarURL?.absoluteString == "https://example.invalid/avatar.png", "\(label)")
            #expect(app.scopes == ["repo", "read:org"], "\(label)")
            #expect(app.tokenExpiresAt == sample.lastSynced, "\(label)")
            guard case .gitHubApp(let token, let expiresAt, let refreshToken) = app.credential else {
                Issue.record("\(label): expected a gitHubApp credential")
                continue
            }
            #expect(token == "corpus-access-token", "\(label)")
            #expect(expiresAt == sample.lastSynced, "\(label)")
            #expect(refreshToken == "corpus-refresh-token", "\(label)")

            let pat = try #require(
                GitHubTokenStore(fileURL: snapshot.appendingPathComponent("github-token-pat.json")).load(),
                "\(label)")
            #expect(pat.credential == .personalAccessToken("corpus-pat"), "\(label)")
            // Persisted before scopes were recorded: `nil` means "unknown", never `[]`.
            #expect(pat.scopes == nil, "\(label)")
        }
    }

    @Test func everySnapshotImportsItsExportFile() throws {
        for snapshot in corpus.snapshots {
            let label = snapshot.lastPathComponent
            let data = try Data(contentsOf: snapshot.appendingPathComponent("export.json"))
            let export = try JSONDecoder().decode(ProjectStoreExport.self, from: data)
            #expect(export.formatVersion == ProjectStoreExport.currentFormatVersion, "\(label)")
            #expect(export.projects.map(\.id) == [sample.projectID], "\(label)")
            #expect(export.generatedDiagrams.count == 10, "\(label)")
            #expect(export.freeformDiagrams.map(\.id) == [sample.freeformID], "\(label)")
            #expect(export.managedQualityRules[sample.codebaseID]?.includeGeneratedTypes == true, "\(label)")

            try withTempDirectory { directory in
                let store = ProjectStore(
                    baseDir: directory.appendingPathComponent("store", isDirectory: true),
                    analysisStore: AnalysisStore(directory: directory.appendingPathComponent("analysis"))
                )
                try store.importAllData(export, mode: .replaceAll)
                #expect(store.projects.map(\.id) == [sample.projectID], "\(label)")
                #expect(store.freeformDiagrams[sample.freeformID]?.checkpoints.count == 1, "\(label)")
            }
        }
    }

    // MARK: - Recording

    @Test func recordsANewSnapshotWhenAsked() throws {
        guard let label = corpus.recordingLabel else { return }
        guard let snapshot = try corpus.makeSnapshotDirectory(label: label) else {
            Issue.record("snapshot \"\(label)\" is already committed; recording never rewrites one")
            return
        }

        try withTempDirectory { directory in
            let baseDir = directory.appendingPathComponent("store", isDirectory: true)
            // Through the stores' own writers, so the corpus carries the bytes production writes.
            let store = ProjectStore(
                baseDir: baseDir,
                analysisStore: AnalysisStore(directory: directory.appendingPathComponent("analysis"))
            )
            store.projects = [sample.project]
            for diagram in sample.generatedDiagrams { store.saveGeneratedDiagram(diagram) }
            store.saveFreeformDiagram(sample.freeformDiagram)
            store.saveProject(sample.project)
            try FilterPresetStore(baseDir: baseDir).save(sample.filterPresets, projectID: sample.projectID)
            try FindingsSuppressionStore(baseDir: baseDir)
                .save(sample.suppressionBaseline, projectID: sample.projectID)
            try sample.storedArtifactJSON.write(
                to: baseDir
                    .appendingPathComponent("artifacts", isDirectory: true)
                    .appendingPathComponent("codebase_\(sample.codebaseID.uuidString).json")
            )

            try copyNonEmptyDirectories(
                from: baseDir, to: snapshot.appendingPathComponent("store", isDirectory: true))
        }

        try GitHubTokenStore(fileURL: snapshot.appendingPathComponent("github-token.json"))
            .save(sample.storedGitHubAccount)
        try GitHubTokenStore(fileURL: snapshot.appendingPathComponent("github-token-pat.json"))
            .save(sample.storedPersonalAccessTokenAccount)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        try encoder.encode(sample.export).write(to: snapshot.appendingPathComponent("export.json"))
    }

    // MARK: - Field assertions
    //
    // Deliberately literal rather than compared against `LegacyCorpusAppSample`: a snapshot records
    // what the models held when it was written, so the expectation must not move with the sample.

    private func expectCodebase(_ codebase: Codebase?, label: String) throws {
        let codebase = try #require(codebase, "\(label)")
        #expect(codebase.id == sample.codebaseID, "\(label)")
        #expect(codebase.name == "Corpus Codebase", "\(label)")
        #expect(codebase.directoryPath == "/corpus/sources", "\(label)")
        #expect(codebase.securityScopedBookmark?.data == Data([0x01, 0x02, 0x03, 0x04]), "\(label)")
        #expect(codebase.managedCheckout?.refKind == .tag, "\(label)")
        #expect(codebase.managedCheckout?.lastSyncedCommitSHA == "abcdef0123456789", "\(label)")
        #expect(codebase.managedCheckout?.lastSyncedAt == sample.lastSynced, "\(label)")
        #expect(codebase.hasArtifact, "\(label)")
        #expect(codebase.lastIndexed == sample.lastIndexed, "\(label)")
        #expect(
            codebase.indexedFingerprint == .git(headCommitSHA: "abcdef0123456789", isDirty: false), "\(label)")
        #expect(codebase.hasParseErrors, "\(label)")
        #expect(codebase.parseDiagnosticCount == 3, "\(label)")
        #expect(codebase.qualityCheck?.rulesPath == "/corpus/rules.yml", "\(label)")
        #expect(codebase.qualityCheck?.securityScopedBookmark?.data == Data([0x05, 0x06]), "\(label)")
        #expect(codebase.fileFilter?.rules.map(\.syntax) == [.glob, .regex], "\(label)")
        #expect(codebase.fileFilter?.rules.map(\.action) == [.block, .allow], "\(label)")
        #expect(
            codebase.repository?.remoteURL.absoluteString == "https://example.invalid/corpus.git", "\(label)")
        #expect(codebase.repository?.ref == "v1.2.3", "\(label)")
        #expect(codebase.repository?.subpath == "Sources", "\(label)")
        #expect(codebase.guidedRoute == .dismissed, "\(label)")
        #expect(codebase.analysedRevision == "0123456789abcdef", "\(label)")
    }

    private func expectGeneratedDiagrams(_ store: ProjectStore, label: String) throws {
        let diagrams = sample.generatedDiagrams.compactMap { store.generatedDiagrams[$0.id] }
        #expect(diagrams.count == 10, "\(label)")

        // Every `Content` case's JSON shape, in the order the snapshot recorded them.
        let types = diagrams.map(\.content.type.rawValue)
        #expect(
            types == [
                "class", "sequence", "state", "state", "package",
                "callGraph", "callGraph", "callGraph", "moduleCoupling", "hotspot"
            ],
            "\(label)"
        )
        #expect(diagrams.map(\.callGraphScope) == [
            nil, nil, nil, nil, nil, .wholeCodebase, .type("Corpus.Service"), .module("AcaiCore"), nil, nil
        ], "\(label)")

        let first = try #require(diagrams.first, "\(label)")
        #expect(first.name == "Corpus Diagram 1", "\(label)")
        #expect(!first.isNameUserDefined, "\(label)")
        #expect(first.codebaseID == sample.codebaseID, "\(label)")
        #expect(first.comparisonGitRef == "feature/corpus", "\(label)")
        #expect(first.comparisonBaseRef == "main", "\(label)")
        #expect(first.packageDiagramFilter?.kind == .class, "\(label)")
        #expect(first.callGraphFilter?.minMembers == 2, "\(label)")
        #expect(first.nodePositions["Corpus.Service"]?.x == 12, "\(label)")
        #expect(first.nodeSizes["Corpus.Service"]?.height == 120, "\(label)")
        #expect(first.canvasScale == 0.75, "\(label)")
        #expect(first.createdDate == sample.lastIndexed, "\(label)")
        #expect(first.lastModified == sample.lastSynced, "\(label)")

        let classConfiguration = try #require(first.classConfiguration, "\(label)")
        #expect(!classConfiguration.showProperties, "\(label)")
        #expect(classConfiguration.propertyVisibility == ["Corpus.Service": true], "\(label)")
        #expect(classConfiguration.grouping == .directory, "\(label)")
        #expect(classConfiguration.minimumAccessLevel == .internal, "\(label)")
        #expect(!classConfiguration.hideGeneratedTypes, "\(label)")
        #expect(classConfiguration.focus?.direction == .both, "\(label)")
        #expect(classConfiguration.focus?.includedRelationshipKinds == [.inheritance, .dependency], "\(label)")

        let sequenceConfiguration = try #require(diagrams[1].sequenceConfiguration, "\(label)")
        #expect(sequenceConfiguration.entryTypeName == "Corpus.Service", "\(label)")
        #expect(sequenceConfiguration.maxDepth == 4, "\(label)")
        #expect(sequenceConfiguration.typeMapping == ["any Store": "DiskStore"], "\(label)")

        let stateConfiguration = try #require(diagrams[2].stateConfiguration, "\(label)")
        #expect(stateConfiguration.typeName == "Download", "\(label)")
        #expect(stateConfiguration.maxStates == 12, "\(label)")
        // The "not configured yet" state has to stay distinguishable from a configured one.
        #expect(diagrams[3].stateConfiguration == nil, "\(label)")
    }

    private func expectFreeformDiagram(_ store: ProjectStore, label: String) throws {
        let diagram = try #require(store.freeformDiagrams[sample.freeformID], "\(label)")
        #expect(diagram.name == "Corpus Freeform", "\(label)")
        #expect(diagram.canvasScale == 1.25, "\(label)")
        #expect(diagram.canvasOffsetY == 17.5, "\(label)")
        #expect(diagram.createdDate == sample.lastIndexed, "\(label)")
        #expect(diagram.nodes.count == 16, "\(label)")
        #expect(diagram.nodes.map(\.id).first == "corpus-node-0", "\(label)")
        #expect(diagram.nodes.map(\.drawOrder) == Array(0..<16), "\(label)")

        // Every `Node.Content` case, in the order the snapshot recorded them.
        #expect(diagram.nodes.map(\.content.kind) == Self.recordedNodeKinds, "\(label)")
        expectNodeContents(diagram.nodes, label: label)

        #expect(diagram.edges.map(\.kind) == [.aggregation, .dependency, .association], "\(label)")
        #expect(diagram.edges[1].messageOrder == 3, "\(label)")
        #expect(diagram.edges[1].messageKind == .asynchronous, "\(label)")
        #expect(diagram.edges[2].transition?.label == "finished [isValid] / persist()", "\(label)")

        let checkpoint = try #require(diagram.checkpoints.first, "\(label)")
        #expect(checkpoint.id == sample.checkpointID, "\(label)")
        #expect(checkpoint.name == "Before the rewrite", "\(label)")
        #expect(checkpoint.createdDate == sample.lastSynced, "\(label)")
        #expect(checkpoint.nodes.count == 16, "\(label)")
        #expect(checkpoint.edges.count == 3, "\(label)")
    }

    private func expectNodeContents(_ nodes: [FreeformDiagram.Node], label: String) {
        guard case .type(let typeContent) = nodes[0].content else {
            Issue.record("\(label): node 0 is not a .type")
            return
        }
        #expect(typeContent.typeKind == .protocol, "\(label)")
        #expect(typeContent.stereotype == "repository", "\(label)")
        #expect(typeContent.genericParameters == ["Element"], "\(label)")
        #expect(typeContent.properties.first?.isStatic == true, "\(label)")
        #expect(typeContent.properties.first?.accessLevel == .private, "\(label)")
        #expect(typeContent.methods.first?.isAbstract == true, "\(label)")
        #expect(typeContent.methods.first?.parameters == "legacy: String", "\(label)")
        #expect(
            typeContent.methods.first?.structuredParameters
                == [FreeformDiagram.Node.Parameter(name: "id", type: "UUID")],
            "\(label)"
        )
        #expect(typeContent.enumCases.first?.associatedValues == "Error", "\(label)")

        guard case .note(let noteText) = nodes[11].content else {
            Issue.record("\(label): node 11 is not a .note")
            return
        }
        #expect(noteText == "a recorded note", "\(label)")
        #expect(nodes[12].content == .lifeline(.database), "\(label)")
        #expect(nodes[15].content == .method, "\(label)")

        guard case .fragment(let fragment) = nodes[13].content else {
            Issue.record("\(label): node 13 is not a .fragment")
            return
        }
        #expect(fragment.kind == .critical, "\(label)")
        #expect(fragment.operands.first?.guardLabel == "retrying", "\(label)")
        #expect(fragment.operands.first?.lastOrder == 4, "\(label)")
        #expect(nodes[14].content == .state(.choice), "\(label)")
    }

    private static let recordedNodeKinds: [FreeformDiagramNodeKind] = [
        .type(.protocol), .actor, .useCase, .boundary, .component, .package, .deploymentNode,
        .database, .artifact, .subsystem, .entity, .note, .lifeline, .fragment, .state(.choice),
        .callGraphMethod
    ]

    // MARK: - Fixtures

    /// The snapshot's `store/` copied into a disposable directory, then opened through
    /// `ProjectStore`'s own init so loading runs exactly as it does in the app. The analysis store
    /// is always injected: `.standard` would be the user's real `~/.acai/analysis`.
    private func withCopiedStore(from snapshot: URL, _ body: (ProjectStore) throws -> Void) throws {
        try withTempDirectory { directory in
            let baseDir = directory.appendingPathComponent("store", isDirectory: true)
            try FileManager.default.copyItem(
                at: snapshot.appendingPathComponent("store", isDirectory: true), to: baseDir)
            let store = ProjectStore(
                baseDir: baseDir,
                analysisStore: AnalysisStore(directory: directory.appendingPathComponent("analysis"))
            )
            try body(store)
        }
    }

    private func withTempDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("acai-legacy-corpus-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    /// Only the directories a store actually wrote into: `ProjectStore.init` also creates empty
    /// `rules`/`git-*` directories that git would not track anyway.
    private func copyNonEmptyDirectories(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let contents = try fileManager.contentsOfDirectory(
            at: source, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        for item in contents {
            guard (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  let children = try? fileManager.contentsOfDirectory(atPath: item.path),
                  !children.isEmpty
            else { continue }
            try fileManager.copyItem(at: item, to: destination.appendingPathComponent(item.lastPathComponent))
        }
    }
}
