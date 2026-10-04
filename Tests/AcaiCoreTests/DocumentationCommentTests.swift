import Testing
@testable import AcaiCore

@Suite("Documentation comment stripping")
struct DocumentationCommentTests {
    private let cStyle = DocumentationComment(linePrefixes: ["///", "//!"], blockOpenings: ["/**", "/*!"])

    @Test func stripsLineMarkersAndJoinsConsecutiveLines() {
        let prose = cStyle.prose(fromLeading: ["/// The zoo.", "///", "/// Holds animals."])
        #expect(prose == "The zoo.\n\nHolds animals.")
    }

    @Test func stripsBlockMarkersAndContinuationDecoration() {
        let prose = cStyle.prose(fromLeading: ["""
        /**
         * The zoo.
         * Holds animals.
         */
        """])
        #expect(prose == "The zoo.\nHolds animals.")
    }

    @Test func keepsRelativeIndentationInsideABlock() {
        let prose = cStyle.prose(fromLeading: ["""
        /**
         * Usage:
         *     zoo.feed()
         */
        """])
        #expect(prose == "Usage:\n    zoo.feed()")
    }

    @Test func singleLineBlockReadsAsItsSentence() {
        #expect(cStyle.prose(fromLeading: ["/** The name. */"]) == "The name.")
    }

    @Test func plainCommentDocumentsNothing() {
        #expect(cStyle.prose(fromLeading: ["// A note to self."]) == nil)
        #expect(cStyle.prose(fromLeading: ["/* A note to self. */"]) == nil)
        #expect(cStyle.prose(fromLeading: []) == nil)
    }

    @Test func plainCommentNearestTheDeclarationDetachesWhatIsAboveIt() {
        #expect(cStyle.prose(fromLeading: ["/// The zoo.", "// TODO: rename"]) == nil)
    }

    @Test func documentationNearestTheDeclarationSurvivesAnUnrelatedCommentAboveIt() {
        #expect(cStyle.prose(fromLeading: ["// TODO: rename", "/// The zoo."]) == "The zoo.")
    }

    @Test func emptyDocumentationIsNone() {
        #expect(cStyle.prose(fromLeading: ["///"]) == nil)
        #expect(cStyle.prose(fromLeading: ["/** */"]) == nil)
        #expect(cStyle.prose(fromLeading: ["/**/"]) == nil)
    }

    @Test func alternativeMarkersAreRecognised() {
        #expect(cStyle.prose(fromLeading: ["//! The zoo."]) == "The zoo.")
        #expect(cStyle.prose(fromLeading: ["/*! The zoo. */"]) == "The zoo.")
    }

    @Test func aBlockWithoutContinuationDecorationKeepsItsOwnShape() {
        let prose = cStyle.prose(fromLeading: ["""
        /**
            The zoo.
              Indented.
        */
        """])
        #expect(prose == "The zoo.\n  Indented.")
    }

    @Test func literalDelimitersAndTheirPrefixAreStripped() {
        let docstring = DocumentationComment(literalDelimiters: ["\"\"\"", "'''", "\"", "'"])
        #expect(docstring.prose(fromLiteral: "\"\"\"The zoo.\"\"\"") == "The zoo.")
        #expect(docstring.prose(fromLiteral: "r'''The zoo.'''") == "The zoo.")
        #expect(docstring.prose(fromLiteral: "\"The zoo.\"") == "The zoo.")
    }

    @Test func aLiteralSpanningLinesIsDedented() {
        let docstring = DocumentationComment(literalDelimiters: ["\"\"\""])
        let prose = docstring.prose(fromLiteral: """
        \"\"\"The zoo.

            Holds animals.
            \"\"\"
        """)
        #expect(prose == "The zoo.\n\nHolds animals.")
    }

    @Test func aLiteralThatIsNotADocstringIsNone() {
        let docstring = DocumentationComment(literalDelimiters: ["\"\"\""])
        #expect(docstring.prose(fromLiteral: "'single quoted'") == nil)
        #expect(docstring.prose(fromLiteral: "\"\"\"\"\"\"") == nil)
    }
}
