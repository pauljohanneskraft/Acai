import Testing
import AcaiCore
import AcaiDiagram
import AcaiRender
@testable import AcaiApp

@Suite("Guided Route Builder")
struct GuidedRouteBuilderTests {
    private let projectID = UUID()
    private let codebaseID = UUID()
    private let language = CodeArtifact.SourceLanguage(rawValue: "test")

    /// `App.run` calls `Worker.process` — nothing calls `App.run`, so it's the call graph's one
    /// entry point. Both `App.run` and `Worker.process` construct `Hub`, giving it the highest
    /// relationship-based fan-in. `Tangled.branchy` carries the one measured complexity value.
    private func artifact() -> CodeArtifact {
        CodeArtifact(
            metadata: .init(sourceLanguage: language, filePaths: ["A.swift"]),
            types: [
                TypeDeclaration(
                    id: "App", name: "App", qualifiedName: "App", kind: .class, accessLevel: .public,
                    members: [
                        Member(
                            name: "run", kind: .method, accessLevel: .internal,
                            callSites: [CallSite(receiver: .type("Worker"), methodName: "process")],
                            referencedTypeNames: ["Hub"])
                    ]
                ),
                TypeDeclaration(
                    id: "Worker", name: "Worker", qualifiedName: "Worker", kind: .class, accessLevel: .public,
                    members: [
                        Member(
                            name: "process", kind: .method, accessLevel: .internal,
                            referencedTypeNames: ["Hub"])
                    ]
                ),
                TypeDeclaration(id: "Hub", name: "Hub", qualifiedName: "Hub", kind: .class, accessLevel: .public),
                TypeDeclaration(
                    id: "Tangled", name: "Tangled", qualifiedName: "Tangled", kind: .class, accessLevel: .public,
                    members: [
                        Member(name: "branchy", kind: .method, accessLevel: .internal, cyclomaticComplexity: 12)
                    ]
                )
            ]
        )
    }

    private func builder() -> GuidedRouteBuilder {
        let artifact = artifact()
        return GuidedRouteBuilder(
            projectID: projectID, codebaseID: codebaseID, artifact: artifact, metrics: artifact.computeMetrics())
    }

    @Test func entryPointStopIsTheUncalledCaller() throws {
        let route = try #require(builder().build())
        let stop = try #require(route.stops.first { $0.kind == .entryPoint })
        #expect(stop.subject == "App.run")
        #expect(stop.content == .callGraph(.wholeCodebase))
    }

    @Test func mostDependedUponStopFocusesOnTheHighestFanInType() throws {
        let route = try #require(builder().build())
        let stop = try #require(route.stops.first { $0.kind == .mostDependedUpon })
        #expect(stop.subject == "Hub")
        var expected = ClassDiagramConfiguration()
        expected.focus = FocusConfiguration(rootTypeName: "Hub", direction: .dependents)
        #expect(stop.content == .classDiagram(expected))
    }

    @Test func mostComplexStopFocusesOnTheTypeWithTheHighestComplexity() throws {
        let route = try #require(builder().build())
        let stop = try #require(route.stops.first { $0.kind == .mostComplex })
        #expect(stop.subject == "Tangled")
        var expected = ClassDiagramConfiguration()
        expected.focus = FocusConfiguration(rootTypeName: "Tangled")
        #expect(stop.content == .classDiagram(expected))
    }

    @Test func stopsAreOrderedEntryThenDependedUponThenComplexity() throws {
        let route = try #require(builder().build())
        #expect(route.stops.map(\.kind) == [.entryPoint, .mostDependedUpon, .mostComplex])
    }

    @Test func tiedFanInBreaksAlphabeticallyByName() throws {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: language, filePaths: ["A.swift"]),
            types: [
                TypeDeclaration(
                    id: "Origin", name: "Origin", qualifiedName: "Origin", kind: .class, accessLevel: .public,
                    members: [
                        Member(
                            name: "wire", kind: .method, accessLevel: .internal,
                            referencedTypeNames: ["Bravo", "Alpha"])
                    ]
                ),
                TypeDeclaration(id: "Bravo", name: "Bravo", qualifiedName: "Bravo", kind: .class, accessLevel: .public),
                TypeDeclaration(id: "Alpha", name: "Alpha", qualifiedName: "Alpha", kind: .class, accessLevel: .public)
            ]
        )
        let route = try #require(GuidedRouteBuilder(
            projectID: projectID, codebaseID: codebaseID, artifact: artifact, metrics: artifact.computeMetrics()
        ).build())
        let stop = try #require(route.stops.first { $0.kind == .mostDependedUpon })
        #expect(stop.subject == "Alpha")
    }

    @Test func buildReturnsNilWhenNoStopResolves() {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: language, filePaths: ["A.swift"]),
            types: [
                TypeDeclaration(id: "Empty", name: "Empty", qualifiedName: "Empty", kind: .class, accessLevel: .public)
            ]
        )
        let route = GuidedRouteBuilder(
            projectID: projectID, codebaseID: codebaseID, artifact: artifact, metrics: artifact.computeMetrics()
        ).build()
        #expect(route == nil)
    }
}
