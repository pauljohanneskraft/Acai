import Foundation
import Testing
@testable import AcaiCore

@Suite("Core: Cohesion partition & stable-dependencies")
struct CohesionAndStabilityMetricsTests {

    private func type(
        _ name: String, kind: TypeKind = .class, module: String, members: [Member] = []
    ) -> TypeDeclaration {
        TypeDeclaration(
            id: name, name: name, qualifiedName: name, kind: kind, accessLevel: .internal, members: members,
            location: SourceLocation(filePath: "Sources/\(module)/\(name).swift", line: 1, column: 1))
    }

    private func method(_ name: String, writes field: String) -> Member {
        Member(name: name, kind: .method, accessLevel: .internal, assignments: [
            VariableAssignment(targetName: field, op: .assign, value: .init(kind: .expression, text: "0"))
        ])
    }

    private func method(_ name: String, reads field: String) -> Member {
        Member(name: name, kind: .method, accessLevel: .internal, fieldReads: [FieldAccess(name: field)])
    }

    @Test func lcomComponentsReportTheMemberPartition() {
        // No shared field, no mutual call between the two groups — the clusters this produces name
        // *how* to split the type.
        let declared = type("Service", module: "App", members: [
            Member(name: "file", kind: .property, accessLevel: .internal),
            Member(name: "socket", kind: .property, accessLevel: .internal),
            method("open", writes: "file"),
            method("close", reads: "file"),
            method("connect", writes: "socket"),
            method("disconnect", reads: "socket")
        ])
        let analysis = LcomAnalysis(type: declared)
        #expect(analysis.componentCount == 2)
        #expect(analysis.components == [["close", "open"], ["connect", "disconnect"]])
    }

    @Test func cohesiveTypeReportsASingleCluster() {
        let declared = type("Counter", module: "App", members: [
            Member(name: "value", kind: .property, accessLevel: .internal),
            method("increment", writes: "value"),
            method("read", reads: "value")
        ])
        #expect(LcomAnalysis(type: declared).components == [["increment", "read"]])
    }

    @Test func staticMembersLeaveCohesionUnchanged() {
        // A `static` member cannot touch instance state, so counting it guaranteed a component of its
        // own and inflated every type carrying a helper.
        let instanceMembers: [Member] = [
            Member(name: "value", kind: .property, accessLevel: .internal),
            method("increment", writes: "value"),
            method("read", reads: "value")
        ]
        let helpers: [Member] = [
            Member(name: "describe", kind: .method, accessLevel: .internal, modifiers: [.static]),
            Member(name: "make", kind: .method, accessLevel: .internal, modifiers: [.class])
        ]
        let withHelpers = LcomAnalysis(type: type("Counter", module: "App", members: instanceMembers + helpers))
        #expect(withHelpers.componentCount == 1)
        #expect(withHelpers.components == [["increment", "read"]])
    }

    @Test func computedPropertiesCountAsBehaviour() {
        // A computed property's accessor is code reaching into the same field the methods use, so it
        // joins their cluster rather than being invisible to cohesion.
        let declared = type("Counter", module: "App", members: [
            Member(name: "value", kind: .property, accessLevel: .internal),
            Member(name: "doubled", kind: .property, accessLevel: .internal, isComputed: true,
                   fieldReads: [FieldAccess(name: "value")]),
            method("increment", writes: "value")
        ])
        #expect(LcomAnalysis(type: declared).components == [["doubled", "increment"]])
    }

    @Test func initialisersDoNotFuseUnrelatedClusters() {
        // An initialiser populating every stored property would link them all, collapsing the metric
        // to 1 for any type with a memberwise initialiser.
        let declared = type("Service", module: "App", members: [
            Member(name: "file", kind: .property, accessLevel: .internal),
            Member(name: "socket", kind: .property, accessLevel: .internal),
            Member(name: "init", kind: .initializer, accessLevel: .internal, assignments: [
                VariableAssignment(targetName: "file", op: .assign, value: .init(kind: .expression, text: "0")),
                VariableAssignment(targetName: "socket", op: .assign, value: .init(kind: .expression, text: "0"))
            ]),
            method("open", writes: "file"),
            method("connect", writes: "socket")
        ])
        #expect(LcomAnalysis(type: declared).componentCount == 2)
    }

    @Test func stableDependencyPrincipleFlagsDependencyOnLessStableModule() {
        func using(_ name: String, module: String, uses target: String?) -> TypeDeclaration {
            let members = target.map {
                [Member(name: "use", kind: .method, accessLevel: .internal, referencedTypeNames: [$0])]
            } ?? []
            return type(name, module: module, members: members)
        }
        // P1, P2 depend on Api.Hub; Api.Hub depends on Impl.Worker; Impl.Worker depends on Deep.Sink.
        // → I(Api)=1/3, I(Impl)=1/2, so Api → Impl is a dependency on a *less*-stable module (SDP breach);
        //   Impl → Deep (I=0) is a healthy dependency on a more-stable module and must not be flagged.
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: CodeArtifact.SourceLanguage(rawValue: "swift")),
            types: [
                using("P1", module: "P1", uses: "Hub"),
                using("P2", module: "P2", uses: "Hub"),
                using("Hub", module: "Api", uses: "Worker"),
                using("Worker", module: "Impl", uses: "Sink"),
                using("Sink", module: "Deep", uses: nil)
            ]
        ).enriched()
        let metrics = artifact.computeMetrics()
        #expect(metrics.modules.first { $0.name == "Api" }?.stableDependencyViolations == ["Impl"])
        #expect(metrics.modules.first { $0.name == "Impl" }?.stableDependencyViolations.isEmpty == true)
    }
}
