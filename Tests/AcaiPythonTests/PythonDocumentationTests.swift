import Testing
@testable import AcaiCore
@testable import AcaiPython

@Suite("Python: Docstrings")
struct PythonDocumentationTests {
    private let parser = PythonCodeParser()

    private func artifact(_ source: String) -> CodeArtifact {
        parser.parse(source: source, fileName: "zoo.py")
    }

    @Test func aClassDocstringIsItsDocumentation() {
        let types = artifact("""
        class Zoo:
            \"\"\"The zoo.

            Holds animals.
            \"\"\"

            def feed(self) -> None:
                \"\"\"Feeds everyone.\"\"\"
                pass

            def clean(self):
                pass
        """).types
        let zoo = types.first
        #expect(zoo?.documentation == "The zoo.\n\nHolds animals.")
        #expect(zoo?.members.first { $0.name == "feed" }?.documentation == "Feeds everyone.")
        #expect(zoo?.members.first { $0.name == "clean" }?.documentation == nil)
    }

    @Test func aCommentAboveADeclarationDocumentsNothing() {
        let types = artifact("""
        # The zoo, allegedly.
        class Zoo:
            pass
        """).types
        #expect(types.first?.documentation == nil)
    }

    @Test func singleQuotedAndPrefixedDocstringsAreRead() {
        let types = artifact("""
        class Zoo:
            'The zoo.'

        class Keeper:
            r\"\"\"A keeper.\"\"\"
        """).types
        #expect(types.first { $0.name == "Zoo" }?.documentation == "The zoo.")
        #expect(types.first { $0.name == "Keeper" }?.documentation == "A keeper.")
    }

    @Test func decoratedAndNestedDeclarationsAreDocumented() {
        let artifact = artifact("""
        import functools

        @functools.cache
        class Zoo:
            \"\"\"The zoo.\"\"\"

            class Inner:
                \"\"\"An inner helper.\"\"\"

            @property
            def total(self):
                \"\"\"How many there are.\"\"\"
                return 0

        @functools.cache
        def main():
            \"\"\"Boots the app.\"\"\"
            pass
        """)
        let zoo = artifact.types.first { $0.name == "Zoo" }
        #expect(zoo?.documentation == "The zoo.")
        #expect(zoo?.nestedTypes.first?.documentation == "An inner helper.")
        #expect(zoo?.members.first { $0.name == "total" }?.documentation == "How many there are.")
        #expect(artifact.freestandingFunctions.first { $0.name == "main" }?.documentation == "Boots the app.")
    }

    @Test func anEnumClassAndItsMethodsAreDocumented() {
        let types = artifact("""
        from enum import Enum

        class Species(Enum):
            \"\"\"What an animal can be.\"\"\"

            DOG = "dog"

            def label(self):
                \"\"\"A readable name.\"\"\"
                return self.value
        """).types
        let species = types.first { $0.name == "Species" }
        #expect(species?.documentation == "What an animal can be.")
        #expect(species?.enumCases.contains { $0.name == "DOG" } == true)
        #expect(species?.members.first { $0.name == "label" }?.documentation == "A readable name.")
    }

    @Test func aSingleQuotedDocstringMayHoldDoubleQuotes() {
        let types = artifact("""
        class Zoo:
            def greet(self):
                'Say "hi".'
        """).types
        #expect(types.first?.members.first { $0.name == "greet" }?.documentation == "Say \"hi\".")
    }

    @Test func aStringThatIsNotTheFirstStatementIsNotADocstring() {
        let types = artifact("""
        class Zoo:
            name = "zoo"
            \"\"\"Not documentation.\"\"\"
        """).types
        #expect(types.first?.documentation == nil)
    }
}
