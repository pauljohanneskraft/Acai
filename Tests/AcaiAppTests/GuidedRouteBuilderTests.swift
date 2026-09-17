import Foundation
import Testing
import AcaiCore
import AcaiDiagram
import AcaiRender
@testable import AcaiApp

@Suite("Guided Route Builder")
struct GuidedRouteBuilderTests {
    private let language = CodeArtifact.SourceLanguage(rawValue: "test")

    /// `App.run` is the only uncalled caller, `Hub` is referenced by both methods, and `Tangled.branchy`
    /// carries the one measured complexity.
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

    private func stops(for artifact: CodeArtifact) -> [GuidedRouteStop] {
        GuidedRouteBuilder(artifact: artifact, metrics: artifact.computeMetrics()).stops
    }

    @Test func entryPointStopIsTheUncalledCallerScopedToItsType() throws {
        let stop = try #require(stops(for: artifact()).first { $0.kind == .entryPoint })
        #expect(stop.subject == "App.run")
        #expect(stop.content == .callGraph(.type("App")))
    }

    @Test func aFreeFunctionEntryPointOpensTheWholeCodebaseCallGraph() throws {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: language, filePaths: ["main.swift"]),
            types: [
                TypeDeclaration(
                    id: "Worker", name: "Worker", qualifiedName: "Worker", kind: .class, accessLevel: .public,
                    members: [Member(name: "process", kind: .method, accessLevel: .internal)]
                )
            ],
            freestandingFunctions: [
                Member(
                    name: "main", kind: .method, accessLevel: .internal,
                    callSites: [CallSite(receiver: .type("Worker"), methodName: "process")])
            ]
        )
        let stop = try #require(stops(for: artifact).first { $0.kind == .entryPoint })
        #expect(stop.subject == "main")
        #expect(stop.content == .callGraph(.wholeCodebase))
    }

    @Test func mostDependedUponStopFocusesOnTheHighestFanInType() throws {
        let stop = try #require(stops(for: artifact()).first { $0.kind == .mostDependedUpon })
        #expect(stop.subject == "Hub")
        var expected = ClassDiagramConfiguration()
        expected.focus = FocusConfiguration(rootTypeName: "Hub", direction: .dependents)
        #expect(stop.content == .classDiagram(expected))
    }

    @Test func mostComplexStopFocusesOnTheTypeWithTheHighestComplexity() throws {
        let stop = try #require(stops(for: artifact()).first { $0.kind == .mostComplex })
        #expect(stop.subject == "Tangled")
        var expected = ClassDiagramConfiguration()
        expected.focus = FocusConfiguration(rootTypeName: "Tangled")
        #expect(stop.content == .classDiagram(expected))
    }

    @Test func stopsAreOrderedEntryThenDependedUponThenComplexity() {
        let kinds: [GuidedRouteStop.Kind] = stops(for: artifact()).map(\.kind)
        #expect(kinds == [.entryPoint, .mostDependedUpon, .mostComplex])
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
        let stop = try #require(stops(for: artifact).first { $0.kind == .mostDependedUpon })
        #expect(stop.subject == "Alpha")
    }

    @Test func noStopResolvesForACodebaseWithoutSignal() {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: language, filePaths: ["A.swift"]),
            types: [
                TypeDeclaration(id: "Empty", name: "Empty", qualifiedName: "Empty", kind: .class, accessLevel: .public)
            ]
        )
        #expect(stops(for: artifact).isEmpty)
    }
}
