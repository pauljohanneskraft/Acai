import Testing
@testable import AcaiJS
@testable import AcaiCore

/// The grammar is picked from the file extension, and getting that wrong is silent: the TypeScript
/// grammar has no JSX, so it yields a partial artifact with `ERROR` nodes rather than refusing the
/// file. These pin the routing by its observable consequence — the diagnostics — in both directions.
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

    /// The same source under the TypeScript grammar, which is what `.tsx` used to get. Asserting the
    /// failure keeps the two grammars from being quietly collapsed back into one.
    @Test("the TypeScript grammar cannot read the same component")
    func typeScriptGrammarRejectsJSX() {
        let artifact = JSCodeParser().parse(source: Self.component, fileName: "badge.ts")
        #expect(!artifact.metadata.parseDiagnostics.isEmpty)
    }

    @Test("a .jsx component parses with no diagnostics")
    func jsxParsesCleanly() {
        let source = """
        export class Badge extends React.Component {
            render() {
                return <span className="badge">{this.props.label}</span>;
            }
        }
        """
        let artifact = JSCodeParser(isTypeScript: false).parse(source: source, fileName: "badge.jsx")
        #expect(artifact.metadata.parseDiagnostics.isEmpty)
        #expect(artifact.types.map(\.name) == ["Badge"])
    }

    /// `.mts`/`.cts` take the TypeScript grammar, so their type annotations still have to survive.
    @Test("TypeScript module extensions keep their annotations", arguments: ["badge.mts", "badge.cts"])
    func moduleExtensionsParseAsTypeScript(fileName: String) {
        let source = """
        export class Badge {
            label: string = "";
        }
        """
        let artifact = JSCodeParser().parse(source: source, fileName: fileName)
        #expect(artifact.metadata.parseDiagnostics.isEmpty)
        #expect(artifact.types.first?.members.first?.type?.name == "string")
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
