import Testing
@testable import UMLCore
@testable import UMLDiagram

/// `--theme` is opt-in: without it the renderers emit structural output (no cosmetic colours) so
/// the consumer themes it; with it they emit the palette inline (DOT) or as a Mermaid init
/// directive. Semantic colours (state pseudo-state markers) are always present.
@Suite("Theming")
struct ThemingTests {

    private var classArtifact: CodeArtifact {
        CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Test.swift"]),
            types: [
                TypeDeclaration(
                    id: "Animal", name: "Animal", qualifiedName: "Animal", kind: .class,
                    members: [Member(name: "name", kind: .property, type: TypeReference(name: "String"))]
                )
            ]
        )
    }

    // MARK: - Class DOT

    @Test func classDOTIsStructuralWithoutTheme() {
        let dot = DOTGenerator(options: ClassDiagramOptions(theme: nil)).generate(from: classArtifact)
        #expect(!dot.contains("bgcolor"))
        #expect(!dot.contains("BGCOLOR"))
        #expect(!dot.contains("<FONT COLOR="))
        // Structure is retained.
        #expect(dot.contains("digraph UML"))
        #expect(dot.contains("<TABLE BORDER=\"1\""))
    }

    @Test func classDOTAppliesThemeInline() {
        let dot = DOTGenerator(options: ClassDiagramOptions(theme: .dark)).generate(from: classArtifact)
        #expect(dot.contains("bgcolor=\"#1e1e1e\""))
        #expect(dot.contains("BGCOLOR=\"#2d2d2d\""))
        #expect(dot.contains("<FONT COLOR=\"#cccccc\">"))
    }

    // MARK: - Class Mermaid

    @Test func classMermaidOmitsInitWithoutTheme() {
        let renderer = ClassDiagramMermaidRenderer(options: ClassDiagramOptions(theme: nil))
        let mermaid = renderer.generate(from: classArtifact)
        #expect(mermaid.hasPrefix("classDiagram"))
        #expect(!mermaid.contains("%%{init"))
    }

    @Test func classMermaidPrependsInitDirectiveWhenThemed() {
        let renderer = ClassDiagramMermaidRenderer(options: ClassDiagramOptions(theme: .dark))
        let mermaid = renderer.generate(from: classArtifact)
        #expect(mermaid.hasPrefix("%%{init: {'theme':'base'"))
        #expect(mermaid.contains("'background':'#1e1e1e'"))
    }

    // MARK: - State DOT (semantic vs cosmetic)

    private var stateDiagram: StateDiagram {
        StateDiagram(
            states: [
                StateDiagram.State(id: "i", name: "", kind: .initial),
                StateDiagram.State(id: "a", name: "Active", kind: .normal)
            ],
            transitions: [StateDiagram.Transition(from: "i", to: "a")]
        )
    }

    @Test func stateDOTKeepsSemanticMarkerButDropsCosmeticWhenUnthemed() {
        let dot = StateDiagramDOTRenderer(theme: nil).render(stateDiagram)
        #expect(!dot.contains("bgcolor"))
        // Pseudo-state marker is semantic — always filled (black when unthemed).
        #expect(dot.contains("fillcolor=\"black\""))
        // Normal states carry no cosmetic fill.
        #expect(dot.contains("[shape=Mrecord label=\"Active\"]"))
    }

    @Test func stateDOTUsesThemeMarkerAndFillsWhenThemed() {
        let dot = StateDiagramDOTRenderer(theme: .dark).render(stateDiagram)
        #expect(dot.contains("bgcolor=\"#1e1e1e\""))
        // Marker uses the theme border colour so it stays visible on the dark background.
        #expect(dot.contains("fillcolor=\"#cccccc\""))
        #expect(dot.contains("fillcolor=\"#2d2d2d\""))
    }
}
