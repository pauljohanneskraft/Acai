import AcaiCore
import Testing
@testable import AcaiTreeSitter

@Suite("Documentation Reader")
struct DocumentationReaderTests {

    private let javadoc = DocumentationComment(
        linePrefixes: ["///"],
        blockOpenings: ["/**"],
        blockClosing: "*/",
        continuationMarker: "*",
        literalDelimiters: ["\""])

    private var reader: DocumentationReader {
        DocumentationReader(
            convention: javadoc, commentNodeTypes: ["block_comment", "line_comment"])
    }

    private func documentation(aboveFirst nodeType: String, in source: String) throws -> String? {
        let fixture = try #require(JavaFixture(source))
        let node = try #require(fixture.firstNode(ofType: nodeType))
        return reader.documentation(above: node, in: fixture.context)
    }

    @Test("A documentation block directly above a declaration is its prose, decoration stripped")
    func blockCommentAboveIsRead() throws {
        let prose = try documentation(aboveFirst: "class_declaration", in: """
        /**
         * Stores and retrieves orders.
         * Second line.
         */
        class Repository {}
        """)
        #expect(prose == "Stores and retrieves orders.\nSecond line.")
    }

    @Test("Consecutive documentation lines form one run")
    func lineCommentRunIsJoined() throws {
        let prose = try documentation(aboveFirst: "class_declaration", in: """
        /// Stores orders.
        /// And retrieves them.
        class Repository {}
        """)
        #expect(prose == "Stores orders.\nAnd retrieves them.")
    }

    @Test("A comment that is not documentation, or is separated by a blank line, is not attached")
    func unattachedCommentsAreIgnored() throws {
        #expect(try documentation(aboveFirst: "class_declaration", in: """
        // Just a note.
        class Repository {}
        """) == nil)
        #expect(try documentation(aboveFirst: "class_declaration", in: """
        /** A file header. */

        class Repository {}
        """) == nil)
    }

    @Test("A comment trailing the code on its own line documents nothing below it")
    func trailingCommentIsNotAttached() throws {
        let prose = try documentation(aboveFirst: "method_declaration", in: """
        class Repository {
            int x = 1; /// Trails the field.
            void save() {}
        }
        """)
        #expect(prose == nil)
    }

    @Test("A wrapper node that is not itself a declaration is looked through")
    func transparentParentIsFollowed() throws {
        let fixture = try #require(JavaFixture("""
        /// Stores orders.
        class Repository {}
        """))
        let body = try #require(fixture.firstNode(ofType: "class_body"))
        // The body carries no comment run of its own; `class_declaration` stands in for the wrapper
        // node types (`export …`, `template …`) a language that has them would list.
        let opaque = DocumentationReader(convention: javadoc, commentNodeTypes: ["line_comment"])
        #expect(opaque.documentation(above: body, in: fixture.context) == nil)
        let transparent = DocumentationReader(
            convention: javadoc, commentNodeTypes: ["line_comment"],
            transparentParentTypes: ["class_declaration"])
        #expect(transparent.documentation(above: body, in: fixture.context) == "Stores orders.")
    }

    @Test("A string literal that is itself the documentation has its quotes removed")
    func literalDocumentationIsRead() throws {
        let fixture = try #require(JavaFixture("""
        class Repository {
            String doc = "Stores orders.";
        }
        """))
        let literal = try #require(fixture.firstNode(ofType: "string_literal"))
        #expect(reader.documentation(inLiteral: literal, in: fixture.context) == "Stores orders.")
    }
}
