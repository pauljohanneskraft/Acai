import Foundation
import AcaiCore
import AcaiDiagram
import AcaiQuality
import AcaiRender
@testable import AcaiApp

/// The shapes a legacy-decode snapshot of the app's persisted state is recorded from. Ids and dates
/// are fixed so a decode assertion can check exact values, and every enum case a persisted model
/// can hold appears somewhere — the corpus only protects the fields it actually contains.
struct LegacyCorpusAppSample {
    let projectID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    let codebaseID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    let freeformID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    let checkpointID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
    let presetID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
    let lastIndexed = Date(timeIntervalSince1970: 1_700_000_000)
    let lastSynced = Date(timeIntervalSince1970: 1_700_000_500)

    /// One generated diagram per `GeneratedDiagram.Content` case, each under a fixed id, so every
    /// case's JSON shape is committed.
    var generatedDiagrams: [GeneratedDiagram] {
        [
            diagram(index: 1, content: .classDiagram(classConfiguration)),
            diagram(index: 2, content: .sequenceDiagram(sequenceConfiguration)),
            diagram(index: 3, content: .stateDiagram(StateDiagramConfiguration(
                typeName: "Download", variableName: "state", maxStates: 12, filter: selector))),
            diagram(index: 4, content: .stateDiagram(nil)),
            diagram(index: 5, content: .packageDiagram),
            diagram(index: 6, content: .callGraph(.wholeCodebase)),
            diagram(index: 7, content: .callGraph(.type("Corpus.Service"))),
            diagram(index: 8, content: .callGraph(.module("AcaiCore"))),
            diagram(index: 9, content: .moduleCoupling),
            diagram(index: 10, content: .hotspot)
        ]
    }

    var project: Project {
        Project(
            id: projectID,
            title: "Corpus Project",
            subtitle: "Recorded persistence",
            codebases: [codebase],
            generatedDiagramIDs: generatedDiagrams.map(\.id),
            freeformDiagramIDs: [freeformID]
        )
    }

    var codebase: Codebase {
        Codebase(
            id: codebaseID,
            name: "Corpus Codebase",
            directoryPath: "/corpus/sources",
            securityScopedBookmark: bookmark(base64: "AQIDBA=="),
            managedCheckout: ManagedCheckout(
                refKind: .tag, lastSyncedCommitSHA: "abcdef0123456789", lastSyncedAt: lastSynced),
            hasArtifact: true,
            lastIndexed: lastIndexed,
            indexedFingerprint: .git(headCommitSHA: "abcdef0123456789", isDirty: false),
            hasParseErrors: true,
            parseDiagnosticCount: 3,
            qualityCheck: QualityCheckConfiguration(
                rulesPath: "/corpus/rules.yml",
                securityScopedBookmark: bookmark(base64: "BQY=")
            ),
            fileFilter: FileFilter(rules: [
                FileFilter.Rule(pattern: "*", syntax: .glob, action: .block),
                FileFilter.Rule(pattern: "^Sources/.*\\.swift$", syntax: .regex, action: .allow)
            ]),
            repository: CodebaseRepositoryReference(
                remoteURL: URL(string: "https://example.invalid/corpus.git")!,
                ref: "v1.2.3",
                subpath: "Sources"
            ),
            guidedRoute: .dismissed,
            analysedRevision: "0123456789abcdef"
        )
    }

    var freeformDiagram: FreeformDiagram {
        FreeformDiagram(
            id: freeformID,
            name: "Corpus Freeform",
            nodes: freeformNodes,
            edges: freeformEdges,
            canvasScale: 1.25,
            canvasOffsetX: -40,
            canvasOffsetY: 17.5,
            createdDate: lastIndexed,
            lastModified: lastSynced,
            checkpoints: [
                FreeformDiagram.Checkpoint(
                    id: checkpointID,
                    name: "Before the rewrite",
                    createdDate: lastSynced,
                    nodes: freeformNodes,
                    edges: freeformEdges
                )
            ]
        )
    }

    var filterPresets: FilterPresetList {
        FilterPresetList(
            formatVersion: FilterPresetList.currentFormatVersion,
            presets: [
                FilterPreset(
                    id: presetID,
                    name: "Public core only",
                    selector: selector,
                    fileFilter: FileFilter(rules: [
                        FileFilter.Rule(pattern: "Tests/**", syntax: .glob, action: .block)
                    ])
                )
            ]
        )
    }

    var suppressionBaseline: FindingsSuppressionBaseline {
        FindingsSuppressionBaseline(
            formatVersion: 1,
            suppressedFindingIDs: ["cycle:AcaiCore->AcaiDiagram", "budget:Corpus.Service:members"]
        )
    }

    var storedGitHubAccount: GitHubTokenStore.StoredAccount {
        GitHubTokenStore.StoredAccount(
            credential: .gitHubApp(
                accessToken: "corpus-access-token", expiresAt: lastSynced, refreshToken: "corpus-refresh-token"),
            login: "corpus-user",
            avatarURL: URL(string: "https://example.invalid/avatar.png"),
            scopes: ["repo", "read:org"],
            tokenExpiresAt: lastSynced
        )
    }

    /// A second credential shape, recorded on its own so both `GitHubCredential` cases are covered.
    var storedPersonalAccessTokenAccount: GitHubTokenStore.StoredAccount {
        GitHubTokenStore.StoredAccount(
            credential: .personalAccessToken("corpus-pat"), login: "corpus-pat-user")
    }

    var export: ProjectStoreExport {
        ProjectStoreExport(
            projects: [project],
            generatedDiagrams: generatedDiagrams,
            freeformDiagrams: [freeformDiagram],
            managedQualityRules: [codebaseID: QualityRules(includeGeneratedTypes: true)]
        )
    }

    /// The pre-shared-store `artifacts/codebase_<id>.json` envelope, still read once for migration.
    var storedArtifactJSON: Data {
        get throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
            return try encoder.encode(StoredArtifactEnvelope(formatVersion: 2, artifact: artifact))
        }
    }

    var artifact: CodeArtifact {
        CodeArtifact(
            metadata: CodeArtifact.Metadata(
                sourceLanguage: CodeArtifact.SourceLanguage(rawValue: "swift"),
                filePaths: ["Service.swift"],
                toolVersion: "corpus-1.0"
            ),
            types: [
                TypeDeclaration(
                    id: "Corpus.Service", name: "Service", qualifiedName: "Corpus.Service",
                    kind: .class, accessLevel: .public)
            ]
        )
    }

    /// Mirrors `ProjectStore`'s private envelope, which is not visible even to a `@testable` import.
    struct StoredArtifactEnvelope: Codable {
        var formatVersion: Int
        var artifact: CodeArtifact
    }

    // MARK: - Pieces

    /// `SecurityScopedBookmark`'s only initializer resolves a real URL, so a fixed sample bookmark
    /// comes in through its `Codable` conformance instead.
    private func bookmark(base64: String) -> SecurityScopedBookmark {
        // swiftlint:disable:next force_try
        try! JSONDecoder().decode(
            SecurityScopedBookmark.self, from: Data(#"{"data":"\#(base64)"}"#.utf8))
    }

    private var selector: AcaiQuality.Selector {
        AcaiQuality.Selector(
            module: "Acai*",
            typeGlob: "Corpus.*",
            stereotype: "entity",
            annotation: "observable",
            minimumAccess: .public,
            kind: .class,
            minMembers: 2,
            minNesting: 1,
            explicitIDs: ["Corpus.Service"],
            explicitModules: ["AcaiCore"]
        )
    }

    private var classConfiguration: ClassDiagramConfiguration {
        var configuration = ClassDiagramConfiguration()
        configuration.showProperties = false
        configuration.propertyVisibility = ["Corpus.Service": true]
        configuration.methodVisibility = ["Corpus.Service": false]
        configuration.enumCaseVisibility = ["Corpus.Kind": true]
        configuration.grouping = .directory
        configuration.showExternalTypes = true
        configuration.minimumAccessLevel = .internal
        configuration.hideGeneratedTypes = false
        configuration.focus = FocusConfiguration(
            rootTypeName: "Corpus.Service",
            maxDepth: 2,
            direction: .both,
            includedRelationshipKinds: [.inheritance, .dependency],
            includeInterconnections: true
        )
        configuration.filter = selector
        return configuration
    }

    private var sequenceConfiguration: SequenceDiagramConfiguration {
        SequenceDiagramConfiguration(
            entryTypeName: "Corpus.Service",
            entryMethodName: "run",
            maxDepth: 4,
            typeMapping: ["any Store": "DiskStore"],
            filter: selector
        )
    }

    private func diagram(index: Int, content: GeneratedDiagram.Content) -> GeneratedDiagram {
        GeneratedDiagram(
            id: UUID(uuidString: String(format: "666666%02d-6666-6666-6666-666666666666", index))!,
            name: "Corpus Diagram \(index)",
            isNameUserDefined: index.isMultiple(of: 2),
            content: content,
            codebaseID: codebaseID,
            comparisonGitRef: "feature/corpus",
            comparisonBaseRef: "main",
            packageDiagramFilter: selector,
            callGraphFilter: selector,
            nodePositions: ["Corpus.Service": GeneratedDiagram.NodePosition(x: 12, y: 34)],
            nodeSizes: ["Corpus.Service": GeneratedDiagram.NodeSize(width: 200, height: 120)],
            canvasScale: 0.75,
            canvasOffsetX: 5,
            canvasOffsetY: -5,
            createdDate: lastIndexed,
            lastModified: lastSynced
        )
    }

    /// One node per `FreeformDiagram.Node.Content` case.
    private var freeformNodes: [FreeformDiagram.Node] {
        let contents: [FreeformDiagram.Node.Content] = [
            .type(typeContent), .actor, .useCase, .boundary, .component, .package, .deploymentNode,
            .database, .artifact, .subsystem, .entity, .note(text: "a recorded note"),
            .lifeline(.database), .fragment(fragmentContent), .state(.choice), .method
        ]
        return contents.enumerated().map { index, content in
            FreeformDiagram.Node(
                id: "corpus-node-\(index)",
                name: "Node \(index)",
                content: content,
                positionX: Double(index) * 10,
                positionY: Double(index) * 20,
                width: 180,
                height: 90,
                drawOrder: index
            )
        }
    }

    private var typeContent: FreeformDiagram.Node.TypeContent {
        FreeformDiagram.Node.TypeContent(
            typeKind: .protocol,
            stereotype: "repository",
            properties: [
                FreeformDiagram.Node.Member(
                    id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
                    name: "items", type: "[Item]", accessLevel: .private, isStatic: true)
            ],
            methods: [
                FreeformDiagram.Node.Member(
                    id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
                    name: "load", type: "Void", accessLevel: .public, isAbstract: true,
                    parameters: "legacy: String",
                    structuredParameters: [FreeformDiagram.Node.Parameter(name: "id", type: "UUID")])
            ],
            enumCases: [
                FreeformDiagram.Node.EnumCase(
                    id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
                    name: "failed", associatedValues: "Error")
            ],
            genericParameters: ["Element"]
        )
    }

    private var fragmentContent: FreeformDiagram.Node.FragmentContent {
        FreeformDiagram.Node.FragmentContent(
            kind: .critical,
            operands: [SequenceDiagram.Fragment.Operand(guardLabel: "retrying", firstOrder: 2, lastOrder: 4)]
        )
    }

    private var freeformEdges: [FreeformDiagram.Edge] {
        [
            FreeformDiagram.Edge(
                id: "corpus-edge-relationship", sourceNodeID: "corpus-node-0", targetNodeID: "corpus-node-1",
                kind: .aggregation, label: "owns"),
            FreeformDiagram.Edge(
                id: "corpus-edge-message", sourceNodeID: "corpus-node-12", targetNodeID: "corpus-node-15",
                kind: .dependency, label: "load", messageOrder: 3, messageKind: .asynchronous),
            FreeformDiagram.Edge(
                id: "corpus-edge-transition", sourceNodeID: "corpus-node-14", targetNodeID: "corpus-node-15",
                kind: .association,
                transition: FreeformDiagram.Edge.Transition(
                    event: "finished", guardCondition: "isValid", action: "persist()"))
        ]
    }
}
