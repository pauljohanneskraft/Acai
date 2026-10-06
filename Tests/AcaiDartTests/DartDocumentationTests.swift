import Testing
@testable import AcaiCore
@testable import AcaiDart

@Suite("Dart: Documentation Comments")
struct DartDocumentationTests {
    private let parser = DartCodeParser()

    private func artifact(_ source: String) -> CodeArtifact {
        parser.parse(source: source, fileName: "zoo.dart")
    }

    @Test func lineDocumentationOnAClassAndItsMembers() {
        let types = artifact("""
        /// The zoo.
        ///
        /// Holds animals.
        class Zoo {
          /// The name.
          final String name;
          // Not documentation.
          int count = 0;
          /// Feeds everyone.
          void feed() {}
        }
        """).types
        let zoo = types.first
        #expect(zoo?.documentation == "The zoo.\n\nHolds animals.")
        #expect(zoo?.members.first { $0.name == "name" }?.documentation == "The name.")
        #expect(zoo?.members.first { $0.name == "count" }?.documentation == nil)
        #expect(zoo?.members.first { $0.name == "feed" }?.documentation == "Feeds everyone.")
    }

    @Test func blockDocumentationIsStrippedToProse() {
        let types = artifact("""
        /**
         * The zoo.
         * Holds animals.
         */
        class Zoo {}
        """).types
        #expect(types.first?.documentation == "The zoo.\nHolds animals.")
    }

    @Test func enumsMixinsAndExtensionsAreDocumented() {
        let types = artifact("""
        /// Species.
        enum Species {
          /// A dog.
          dog
        }

        /// Can swim.
        mixin Swimmer {}

        /// Zoo helpers.
        extension ZooHelpers on Zoo {
          /// Counts them.
          int get total => 0;
        }
        """).types
        let species = types.first { $0.name == "Species" }
        #expect(species?.documentation == "Species.")
        #expect(species?.enumCases.first?.documentation == "A dog.")
        #expect(types.first { $0.name == "Swimmer" }?.documentation == "Can swim.")
        let helpers = types.first { $0.name == "ZooHelpers" }
        #expect(helpers?.documentation == "Zoo helpers.")
        #expect(helpers?.members.first { $0.name == "total" }?.documentation == "Counts them.")
    }

    @Test func topLevelFunctionsAndVariablesAreDocumented() {
        let parsed = artifact("""
        /// Boots the app.
        void main() {}

        /// The shared zoo.
        final Zoo shared = Zoo();
        """)
        #expect(parsed.freestandingFunctions.first { $0.name == "main" }?.documentation == "Boots the app.")
        #expect(parsed.globalVariables.first { $0.name == "shared" }?.documentation == "The shared zoo.")
    }

    @Test func aNestedTypeIsDocumented() {
        let types = artifact("""
        class Zoo {
          /// An inner helper.
          static const int limit = 3;
        }

        /// A keeper.
        class Keeper {}
        """).types
        #expect(types.first { $0.name == "Zoo" }?.members.first?.documentation == "An inner helper.")
        #expect(types.first { $0.name == "Keeper" }?.documentation == "A keeper.")
    }

    @Test func aPlainCommentIsNotDocumentation() {
        let types = artifact("""
        // Just a line.
        class Zoo {}
        """).types
        #expect(types.first?.documentation == nil)
    }

    @Test func anUndocumentedNeighbourDoesNotInheritDocumentation() {
        let parsed = artifact("""
        /// The shared zoo.
        final Zoo shared = Zoo();

        final Zoo other = Zoo();
        """)
        #expect(parsed.globalVariables.first { $0.name == "shared" }?.documentation == "The shared zoo.")
        #expect(parsed.globalVariables.first { $0.name == "other" }?.documentation == nil)
    }

    @Test func documentationSurvivesAMemberAnnotation() {
        let zoo = artifact("""
        class Zoo {
          /// Describes the zoo.
          @override
          String toString() => '';

          /// The size.
          @Deprecated('x')
          final int size = 0;
        }
        """).types.first
        #expect(zoo?.members.first { $0.name == "toString" }?.documentation == "Describes the zoo.")
        #expect(zoo?.members.first { $0.name == "size" }?.documentation == "The size.")
    }

    @Test func aFileHeaderSeparatedByABlankLineDocumentsNothing() {
        let types = artifact("""
        /// A file header.

        class Zoo {}
        """).types
        #expect(types.first?.documentation == nil)
    }
}
