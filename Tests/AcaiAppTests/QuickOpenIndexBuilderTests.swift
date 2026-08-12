import Foundation
import Testing
import AcaiCore
import AcaiDiagram
@testable import AcaiApp

/// Quick Open's index: `QuickOpenIndexBuilder.entries()` is the pure computation
/// `QuickOpenView` runs off the main actor — covered directly here (no view needed) so the search
/// surface's actual coverage logic (does a type/method/module/diagram show up at all, with the
/// right identity/subtitle) is verified without driving SwiftUI.
@Suite("QuickOpenIndexBuilder")
struct QuickOpenIndexBuilderTests {
    private func member(_ name: String, kind: MemberKind = .method) -> Member {
        Member(name: name, kind: kind, accessLevel: .public)
    }

    @Test func indexesEveryTypeAndItsMethodsAndModule() {
        let codebaseID = UUID()
        let projectID = UUID()
        let type = TypeDeclaration(
            id: "Widget", name: "Widget", qualifiedName: "Widget", kind: .class, accessLevel: .public,
            members: [member("doWork"), member("value", kind: .property)],
            location: SourceLocation(filePath: "Sources/Widgets/Widget.swift", line: 1, column: 1)
        )
        let artifact = CodeArtifact(metadata: .init(sourceLanguage: .swift, filePaths: []), types: [type])
        let project = Project(
            id: projectID, title: "Demo", subtitle: "",
            codebases: [Codebase(id: codebaseID, name: "Demo Codebase", directoryPath: "/tmp/demo")]
        )
        let builder = QuickOpenIndexBuilder(
            projects: [project], artifacts: [codebaseID: artifact],
            generatedDiagrams: [:], freeformDiagrams: [:]
        )
        let entries = builder.entries()

        let typeEntry = entries.first { $0.kind == .type }
        #expect(typeEntry?.name == "Widget")
        #expect(typeEntry?.reference == .type(id: "Widget"))
        #expect(typeEntry?.subtitle == "Demo — Demo Codebase")

        let methodEntry = entries.first { $0.kind == .method }
        #expect(methodEntry?.name == "Widget.doWork")
        #expect(methodEntry?.reference == .method(typeName: "Widget", methodName: "doWork"))

        // The property isn't a method — no `.method` entry for it.
        #expect(!entries.contains { $0.name.contains("value") })

        let moduleEntry = entries.first { $0.kind == .module }
        #expect(moduleEntry?.name == "Widgets")
        #expect(moduleEntry?.reference == .module(name: "Widgets"))
    }

    @Test func indexesGeneratedAndFreeformDiagramsByName() {
        let projectID = UUID()
        let codebaseID = UUID()
        let generatedID = UUID()
        let freeformID = UUID()
        var project = Project(id: projectID, title: "Demo", subtitle: "", codebases: [
            Codebase(id: codebaseID, name: "Demo Codebase", directoryPath: "/tmp/demo")
        ])
        project.generatedDiagramIDs = [generatedID]
        project.freeformDiagramIDs = [freeformID]
        var generated = GeneratedDiagram(name: "", content: .packageDiagram, codebaseID: codebaseID)
        generated.id = generatedID
        generated.name = "Architecture Overview"
        var freeform = FreeformDiagram(name: "Sketch")
        freeform.id = freeformID

        let builder = QuickOpenIndexBuilder(
            projects: [project], artifacts: [:],
            generatedDiagrams: [generatedID: generated], freeformDiagrams: [freeformID: freeform]
        )
        let entries = builder.entries()

        #expect(entries.contains { $0.kind == .generatedDiagram && $0.name == "Architecture Overview" })
        #expect(entries.contains { $0.kind == .freeformDiagram && $0.name == "Sketch" })
    }

    @Test func emptyProjectListProducesNoEntries() {
        let builder = QuickOpenIndexBuilder(
            projects: [], artifacts: [:], generatedDiagrams: [:], freeformDiagrams: [:]
        )
        #expect(builder.entries().isEmpty)
    }
}
