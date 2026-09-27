import Foundation
import Testing
import AcaiTestSupport
@testable import AcaiCore

/// Decodes every committed snapshot under `__LegacyCorpus__` on every run: `CodableRoundTripTests`
/// only proves a model round-trips against *itself*, which a field rename or a removed key survives
/// intact. These files were written by an earlier build, so they fail when a change stops decoding
/// what is already on a user's disk.
///
/// A deliberate format change **adds a new snapshot** (`ACAI_RECORD_LEGACY_CORPUS=1 swift test
/// --filter LegacyCorpus`, optionally with `ACAI_LEGACY_CORPUS_LABEL`) and never rewrites an
/// existing one — an old snapshot is the only evidence that yesterday's file still decodes.
@Suite("Legacy corpus decode (AcaiCore)", .timeLimit(.minutes(1)))
struct LegacyCorpusDecodeTests {
    private let corpus = LegacyCorpus()

    @Test func theCorpusIsNotEmpty() {
        #expect(!corpus.snapshots.isEmpty, "no snapshot under \(corpus.root.path)")
    }

    @Test func everySnapshotDecodesItsCodeArtifact() throws {
        for snapshot in corpus.snapshots {
            let data = try Data(contentsOf: snapshot.appendingPathComponent("artifact.json"))
            let artifact = try JSONDecoder().decode(CodeArtifact.self, from: data)
            let label = snapshot.lastPathComponent

            #expect(artifact.metadata.sourceLanguage.rawValue == "swift", "\(label)")
            #expect(artifact.metadata.filePaths == ["Service.swift", "Kind.swift"], "\(label)")
            #expect(artifact.metadata.toolVersion == "corpus-1.0", "\(label)")
            #expect(artifact.metadata.parseDiagnostics.map(\.kind) == [.missing], "\(label)")
            #expect(artifact.metadata.parseDiagnostics.first?.location.line == 9, "\(label)")

            try expectService(in: artifact, label: label)
            try expectKindEnum(in: artifact, label: label)
            expectExtension(in: artifact, label: label)
            expectKindsAndRelationships(in: artifact, label: label)
            expectTopLevelDeclarations(in: artifact, label: label)
        }
    }

    @Test func everySnapshotDecodesItsAnalysisStoreEntries() throws {
        for snapshot in corpus.snapshots {
            let store = AnalysisStore(directory: snapshot.appendingPathComponent("analysis", isDirectory: true))
            let label = snapshot.lastPathComponent

            guard case .entry(let git) = store.lookup(named: "entry") else {
                Issue.record("\(label): entry.json did not decode as an AnalysisStore.Entry")
                continue
            }
            #expect(git.formatVersion == 1, "\(label)")
            #expect(git.sourcePath == "/corpus/git-source", "\(label)")
            #expect(
                git.fingerprint == .git(headCommitSHA: "0f1e2d3c4b5a69788796a5b4c3d2e1f001122334", isDirty: true),
                "\(label)"
            )
            #expect(git.artifact.types.contains { $0.id == "Corpus.Service" }, "\(label)")
            #expect(
                git.isCurrent(
                    sourcePath: "/corpus/git-source", fingerprint: git.fingerprint, toolVersion: "corpus-1.0"),
                "\(label)"
            )

            guard case .entry(let fileSystem) = store.lookup(named: "entry-filesystem") else {
                Issue.record("\(label): entry-filesystem.json did not decode as an AnalysisStore.Entry")
                continue
            }
            // The one persisted `Date` in the core corpus: a changed encoding strategy shows up here.
            #expect(
                fileSystem.fingerprint == .fileSystem(
                    latestModification: Date(timeIntervalSince1970: 1_700_000_000),
                    fileCount: 2,
                    contentDigest: 0xdead_beef_cafe_f00d
                ),
                "\(label)"
            )

            // The pre-shared-store shape: a bare `CodeArtifact` with no entry wrapper.
            guard case .legacyArtifact(let bare) = store.lookup(named: "legacy") else {
                Issue.record("\(label): legacy.json did not decode as a bare CodeArtifact")
                continue
            }
            #expect(bare.types.contains { $0.id == "Corpus.Service" }, "\(label)")
        }
    }

    // MARK: - Recording

    @Test func recordsANewSnapshotWhenAsked() throws {
        guard let label = corpus.recordingLabel else { return }
        guard let directory = try corpus.makeSnapshotDirectory(label: label) else {
            Issue.record("snapshot \"\(label)\" is already committed; recording never rewrites one")
            return
        }
        let sample = LegacyCorpusSample()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        try encoder.encode(sample.artifact).write(to: directory.appendingPathComponent("artifact.json"))

        // Through the store's own writer, so the corpus carries the bytes production writes.
        let analysis = directory.appendingPathComponent("analysis", isDirectory: true)
        let store = AnalysisStore(directory: analysis)
        try store.write(
            sample.artifact, sourcePath: "/corpus/git-source", fingerprint: sample.gitFingerprint, named: "entry")
        try store.write(
            sample.artifact, sourcePath: "/corpus/filesystem-source", fingerprint: sample.fileSystemFingerprint,
            named: "entry-filesystem")
        try JSONEncoder().encode(sample.artifact).write(to: analysis.appendingPathComponent("legacy.json"))
    }

    // MARK: - Field assertions
    //
    // Deliberately literal rather than compared against `LegacyCorpusSample`: a snapshot records
    // what the model held when it was written, so the expectation must not move with the sample.

    private func expectService(in artifact: CodeArtifact, label: String) throws {
        let service = try #require(artifact.types.first { $0.id == "Corpus.Service" }, "\(label)")
        #expect(service.kind == .class, "\(label)")
        #expect(service.accessLevel == .public, "\(label)")
        #expect(service.modifiers == [.final, .open], "\(label)")
        #expect(service.namespace == "Corpus", "\(label)")
        #expect(service.annotations == ["@Observable", "@MainActor"], "\(label)")
        #expect(service.sourceLanguage?.rawValue == "swift", "\(label)")
        #expect(service.location == SourceLocation(filePath: "Service.swift", line: 3, column: 1), "\(label)")
        #expect(service.associatedTypes.map(\.name) == ["Output"], "\(label)")
        #expect(
            service.genericParameters.first?.constraints.map(\.kind) == [.conformance, .superclass, .sameType],
            "\(label)"
        )
        #expect(service.inheritedTypes.last?.genericArguments.last?.isArray == true, "\(label)")
        #expect(service.inheritedTypes.last?.genericArguments.last?.isOptional == true, "\(label)")
        #expect(service.nestedTypes.map(\.accessLevel) == [.filePrivate], "\(label)")
        #expect(service.members.map(\.kind) == [.property, .method, .initializer, .deinitializer, .subscript],
                "\(label)")

        let stored = try #require(service.members.first { $0.name == "store" }, "\(label)")
        #expect(stored.setAccessLevel == .private, "\(label)")
        #expect(stored.modifiers == [.lazy, .weak], "\(label)")
        #expect(stored.type == TypeReference(name: "Store", isOptional: true), "\(label)")
        #expect(stored.initialValue?.kind == .nilLiteral, "\(label)")

        let run = try #require(service.members.first { $0.name == "run" }, "\(label)")
        #expect(run.accessLevel == .protected, "\(label)")
        #expect(run.modifiers.map(\.rawValue) == Self.recordedModifierRawValues, "\(label)")
        #expect(run.parameters.first?.isVariadic == true, "\(label)")
        #expect(run.parameters.first?.defaultValue == "Input()", "\(label)")
        #expect(run.parameters.first?.modifiers == [.borrowing], "\(label)")
        #expect(run.callSites.map(\.receiver) == [.selfDispatch, .type("Store"), .free, .unknown], "\(label)")
        #expect(run.assignments.map(\.value.kind)
            == [.enumCase, .numericLiteral, .stringLiteral, .booleanLiteral, .expression], "\(label)")
        #expect(run.assignments.map(\.op) == [.assign, .compound, .assign, .assign, .assign], "\(label)")
        #expect(run.assignments.first?.value.receiverTypeName == "Kind", "\(label)")
        #expect(run.fieldReads.map(\.name) == ["state", "counter"], "\(label)")
        #expect(run.fieldReads.last?.receiver == "Metrics", "\(label)")
        #expect(run.cyclomaticComplexity == 7, "\(label)")
        #expect(run.referencedTypeNames == ["Input", "Output"], "\(label)")
    }

    private func expectKindEnum(in artifact: CodeArtifact, label: String) throws {
        let kind = try #require(artifact.types.first { $0.id == "Corpus.Kind" }, "\(label)")
        #expect(kind.modifiers == [.indirect], "\(label)")
        #expect(kind.enumCases.map(\.name) == ["loading", "named", "failed"], "\(label)")
        #expect(kind.enumCases[1].rawValue == "NAMED", "\(label)")
        #expect(kind.enumCases[2].associatedValues.map(\.internalName) == ["error", "count"], "\(label)")
        #expect(kind.enumCases[2].associatedValues.last?.externalName == "retries", "\(label)")
    }

    private func expectExtension(in artifact: CodeArtifact, label: String) {
        let ext = artifact.types.first { $0.id == "extension.Corpus.Service" }
        #expect(ext?.kind == .extension, "\(label)")
        #expect(ext?.extensionOf == "Corpus.Service", "\(label)")
        #expect(ext?.members.first?.isComputed == true, "\(label)")
    }

    private func expectKindsAndRelationships(in artifact: CodeArtifact, label: String) {
        let recordedKinds = artifact.types
            .filter { $0.namespace == "Corpus.Kinds" }
            .map(\.kind.rawValue)
            .sorted()
        #expect(recordedKinds == Self.recordedTypeKindRawValues.sorted(), "\(label)")

        #expect(artifact.relationships.map(\.kind.rawValue) == Self.recordedRelationshipKindRawValues, "\(label)")
        #expect(artifact.relationships.allSatisfy { $0.sourceLabel == "1" && $0.targetLabel == "0..*" }, "\(label)")
        #expect(artifact.relationships.allSatisfy { $0.origin == "Service.swift" }, "\(label)")
    }

    private func expectTopLevelDeclarations(in artifact: CodeArtifact, label: String) {
        #expect(artifact.freestandingFunctions.map(\.name) == ["makeService"], "\(label)")
        #expect(
            artifact.freestandingFunctions.first?.callSites.first?.receiver == .type("Corpus.Service"), "\(label)")
        #expect(artifact.globalVariables.map(\.name) == ["sharedLimit"], "\(label)")
        #expect(artifact.globalVariables.first?.initialValue?.text == "42", "\(label)")
    }

    private static let recordedTypeKindRawValues = [
        "class", "actor", "struct", "enum", "protocol", "interface", "trait", "typeAlias", "object",
        "extension", "annotation", "module", "record", "mixin"
    ]

    private static let recordedRelationshipKindRawValues = [
        "inheritance", "conformance", "composition", "aggregation", "association", "dependency",
        "extension", "nesting"
    ]

    private static let recordedModifierRawValues = [
        "static", "class", "final", "abstract", "override", "mutating", "nonmutating", "lazy", "weak",
        "unowned", "optional", "required", "convenience", "async", "throws", "rethrows", "nonisolated",
        "consuming", "borrowing", "open", "sealed", "data", "inner", "inline", "suspend", "readonly",
        "declare", "const", "synchronized", "volatile", "transient", "native", "strictfp", "default",
        "factory", "late", "external", "covariant", "indirect", "dynamic", "prefix", "postfix", "infix",
        "isolated"
    ]
}
