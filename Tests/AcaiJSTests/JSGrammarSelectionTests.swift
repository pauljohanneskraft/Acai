import Testing
@testable import AcaiJS
@testable import AcaiCore

/// A wrong grammar is silent: it yields a partial artifact with `ERROR` nodes, so these assert the diagnostics.
@Suite("JS grammar selection")
struct JSGrammarSelectionTests {

    static let component = """
    interface BadgeProps {
        label: string;
    }

    export class Badge extends React.Component<BadgeProps> {
        render() {
            return <span className="badge">{this.props.label}</span>;
        }
    }
    """

    @Test("a .tsx component parses with no diagnostics")
    func tsxParsesCleanly() {
        let artifact = JSCodeParser().parse(source: Self.component, fileName: "badge.tsx")
        #expect(artifact.metadata.parseDiagnostics.isEmpty)
        #expect(artifact.types.map(\.name) == ["BadgeProps", "Badge"])
        #expect(artifact.relationships.contains { $0.target == "React.Component" })
    }

    @Test("the TypeScript grammar cannot read the same component")
    func typeScriptGrammarRejectsJSX() {
        let artifact = JSCodeParser().parse(source: Self.component, fileName: "badge.ts")
        #expect(!artifact.metadata.parseDiagnostics.isEmpty)
    }

    @Test(
        "every JavaScript extension parses JSX with no diagnostics",
        arguments: ["badge.js", "badge.jsx", "badge.mjs", "badge.cjs", "Badge.JSX"]
    )
    func javaScriptExtensionsParseJSX(fileName: String) {
        let source = """
        export class Badge extends React.Component {
            render() {
                return <span className="badge">{this.props.label}</span>;
            }
        }
        """
        let artifact = JSCodeParser(isTypeScript: false).parse(source: source, fileName: fileName)
        #expect(artifact.metadata.parseDiagnostics.isEmpty)
        #expect(artifact.types.map(\.name) == ["Badge"])
    }

    @Test(
        "TypeScript extensions keep the angle-bracket cast TSX cannot read",
        arguments: ["badge.ts", "badge.mts", "badge.cts", "Badge.TS"]
    )
    func typeScriptExtensionsParseCasts(fileName: String) {
        let source = """
        export class Badge {
            label: string = <string>"";
        }
        """
        let artifact = JSCodeParser().parse(source: source, fileName: fileName)
        #expect(artifact.metadata.parseDiagnostics.isEmpty)
        #expect(artifact.types.first?.members.first?.type?.name == "string")
    }

    @Test("TSX cannot read an angle-bracket cast")
    func tsxRejectsCasts() {
        let source = """
        export class Badge {
            label: string = <string>"";
        }
        """
        let artifact = JSCodeParser().parse(source: source, fileName: "badge.tsx")
        #expect(!artifact.metadata.parseDiagnostics.isEmpty)
    }

    @Test("every extension a Node project can hold is claimed by exactly one parser")
    func extensionsAreCompleteAndDisjoint() {
        let typeScript = Set(JSCodeParser().fileExtensions)
        let javaScript = Set(JSCodeParser(isTypeScript: false).fileExtensions)
        #expect(typeScript == ["ts", "mts", "cts", "tsx"])
        #expect(javaScript == ["js", "jsx", "mjs", "cjs"])
        #expect(typeScript.isDisjoint(with: javaScript))
    }
}
