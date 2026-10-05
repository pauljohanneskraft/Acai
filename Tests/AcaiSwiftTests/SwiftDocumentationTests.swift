import Testing
@testable import AcaiCore
@testable import AcaiSwift

@Suite("Swift: Documentation Comments")
struct SwiftDocumentationTests {
    private let parser = SwiftCodeParser()

    private func artifact(_ source: String) -> CodeArtifact {
        parser.parse(source: source, fileName: "Zoo.swift")
    }

    @Test func lineDocumentationOnATypeAndItsMembers() {
        let types = artifact("""
        /// The zoo.
        ///
        /// Holds animals.
        public struct Zoo {
            /// Every animal, by name.
            let animals: [String: Animal]

            /// Feeds everyone.
            func feed() {}
        }
        """).types
        #expect(types.first?.documentation == "The zoo.\n\nHolds animals.")
        #expect(types.first?.members.first { $0.name == "animals" }?.documentation == "Every animal, by name.")
        #expect(types.first?.members.first { $0.name == "feed" }?.documentation == "Feeds everyone.")
    }

    @Test func blockDocumentationIsStrippedToProse() {
        let types = artifact("""
        /**
         * The zoo.
         * Holds animals.
         */
        struct Zoo {}
        """).types
        #expect(types.first?.documentation == "The zoo.\nHolds animals.")
    }

    @Test func documentationSurvivesAttributesAndModifiers() {
        let types = artifact("""
        /// The zoo.
        @MainActor
        public final class Zoo {}
        """).types
        #expect(types.first?.documentation == "The zoo.")
    }

    @Test func anUndocumentedDeclarationHasNone() {
        let types = artifact("""
        // A note to self, not documentation.
        struct Zoo {
            // Also not documentation.
            let count: Int
        }
        """).types
        #expect(types.first?.documentation == nil)
        #expect(types.first?.members.first?.documentation == nil)
    }

    @Test func aPlainCommentBetweenDetachesTheDocumentationAboveIt() {
        let types = artifact("""
        /// The zoo.
        // TODO: rename
        struct Zoo {}
        """).types
        #expect(types.first?.documentation == nil)
    }

    @Test func theDeclarationAboveKeepsItsOwnDocumentation() {
        let types = artifact("""
        /// The zoo.
        struct Zoo {}

        struct Keeper {}
        """).types
        #expect(types.first { $0.name == "Zoo" }?.documentation == "The zoo.")
        #expect(types.first { $0.name == "Keeper" }?.documentation == nil)
    }

    @Test func initializersSubscriptsDeinitializersAndCasesAreDocumented() {
        let types = artifact("""
        /// An animal.
        enum Animal {
            /// A dog.
            case dog
        }

        final class Zoo {
            /// Builds one.
            init() {}
            /// Tears one down.
            deinit {}
            /// The animal at `index`.
            subscript(index: Int) -> Animal { .dog }
        }
        """).types
        let animal = types.first { $0.name == "Animal" }
        #expect(animal?.documentation == "An animal.")
        #expect(animal?.enumCases.first?.documentation == "A dog.")
        let zoo = types.first { $0.name == "Zoo" }
        #expect(zoo?.members.first { $0.kind == .initializer }?.documentation == "Builds one.")
        #expect(zoo?.members.first { $0.kind == .deinitializer }?.documentation == "Tears one down.")
        #expect(zoo?.members.first { $0.kind == .subscript }?.documentation == "The animal at `index`.")
    }

    @Test func extensionsAndFreestandingDeclarationsAreDocumented() {
        let parsed = artifact("""
        /// Zoo helpers.
        extension Zoo {}

        /// Boots the app.
        func main() {}

        /// The shared zoo.
        let shared = Zoo()
        """)
        #expect(parsed.types.first { $0.kind == .extension }?.documentation == "Zoo helpers.")
        #expect(parsed.freestandingFunctions.first { $0.name == "main" }?.documentation == "Boots the app.")
        #expect(parsed.globalVariables.first { $0.name == "shared" }?.documentation == "The shared zoo.")
    }

    @Test func aBlankLineDetachesTheCommentsAboveIt() {
        let types = artifact("""
        /// A file header.

        struct Zoo {}

        /// Something else.

        /// The keeper.
        struct Keeper {}
        """).types
        #expect(types.first { $0.name == "Zoo" }?.documentation == nil)
        #expect(types.first { $0.name == "Keeper" }?.documentation == "The keeper.")
    }

    @Test func aBlankLineHoldingIndentationDetachesToo() {
        let types = artifact("/// A file header.\n    \nstruct Zoo {}\n").types
        #expect(types.first?.documentation == nil)
    }
}
