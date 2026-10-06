import Testing
@testable import AcaiCore
@testable import AcaiJVM

@Suite("Java: Documentation Comments")
struct JavaDocumentationTests {
    private let parser = JavaCodeParser()

    @Test func javadocOnAClassAndItsMembers() {
        let artifact = parser.parse(source: """
        /**
         * The zoo.
         *
         * Holds animals.
         */
        public class Zoo {
            /** The name. */
            private String name;
            // Not documentation.
            private int count;
            /** Feeds everyone. */
            @Override
            public void feed() {}
            /** Builds one. */
            public Zoo() {}
        }
        """, fileName: "Zoo.java")
        let zoo = artifact.types.first
        #expect(zoo?.documentation == "The zoo.\n\nHolds animals.")
        #expect(zoo?.members.first { $0.name == "name" }?.documentation == "The name.")
        #expect(zoo?.members.first { $0.name == "count" }?.documentation == nil)
        #expect(zoo?.members.first { $0.name == "feed" }?.documentation == "Feeds everyone.")
        #expect(zoo?.members.first { $0.kind == .initializer }?.documentation == "Builds one.")
    }

    @Test func javadocStartingOnTheOpeningLineKeepsItsTags() {
        let artifact = parser.parse(source: """
        /** The zoo.
         * @param name its name
         */
        public class Zoo {}
        """, fileName: "Zoo.java")
        #expect(artifact.types.first?.documentation == "The zoo.\n@param name its name")
    }

    @Test func enumsInterfacesRecordsAndNestedTypesAreDocumented() {
        let artifact = parser.parse(source: """
        /** Species. */
        enum Species {
            /** A dog. */
            DOG
        }
        """, fileName: "Species.java")
        let species = artifact.types.first
        #expect(species?.documentation == "Species.")
        #expect(species?.enumCases.first?.documentation == "A dog.")

        let nested = parser.parse(source: """
        /** A keeper. */
        interface Keeper {
            /** Their name. */
            String name();
            /** An inner helper. */
            class Helper {}
        }
        """, fileName: "Keeper.java")
        let keeper = nested.types.first
        #expect(keeper?.documentation == "A keeper.")
        #expect(keeper?.members.first { $0.name == "name" }?.documentation == "Their name.")
        #expect(keeper?.nestedTypes.first?.documentation == "An inner helper.")
    }

    @Test func aPlainCommentIsNotDocumentation() {
        let artifact = parser.parse(source: """
        /* Just a block. */
        public class Zoo {}
        """, fileName: "Zoo.java")
        #expect(artifact.types.first?.documentation == nil)
    }
}

@Suite("Kotlin: Documentation Comments")
struct KotlinDocumentationTests {
    private let parser = KotlinCodeParser()

    @Test func kdocOnAClassAndItsMembers() {
        let artifact = parser.parse(source: """
        /**
         * The zoo.
         *
         * Holds animals.
         */
        class Zoo {
            /** The count. */
            private val count: Int = 0
            // Not documentation.
            private val other: Int = 0
            /** Feeds everyone. */
            fun feed() {}
        }
        """, fileName: "Zoo.kt")
        let zoo = artifact.types.first
        #expect(zoo?.documentation == "The zoo.\n\nHolds animals.")
        #expect(zoo?.members.first { $0.name == "count" }?.documentation == "The count.")
        #expect(zoo?.members.first { $0.name == "other" }?.documentation == nil)
        #expect(zoo?.members.first { $0.name == "feed" }?.documentation == "Feeds everyone.")
    }

    @Test func enumEntriesObjectsAndTopLevelDeclarationsAreDocumented() {
        let artifact = parser.parse(source: """
        /** Species. */
        enum class Species {
            /** A dog. */
            DOG
        }

        /** The registry. */
        object Registry

        /** Boots the app. */
        fun main() {}

        /** The shared zoo. */
        val shared = Zoo()
        """, fileName: "Zoo.kt")
        let species = artifact.types.first { $0.name == "Species" }
        #expect(species?.documentation == "Species.")
        #expect(species?.enumCases.first?.documentation == "A dog.")
        #expect(artifact.types.first { $0.name == "Registry" }?.documentation == "The registry.")
        #expect(artifact.freestandingFunctions.first { $0.name == "main" }?.documentation == "Boots the app.")
        #expect(artifact.globalVariables.first { $0.name == "shared" }?.documentation == "The shared zoo.")
    }

    @Test func aNestedTypeAndACompanionObjectAreDocumented() {
        let artifact = parser.parse(source: """
        class Zoo {
            /** An inner helper. */
            class Helper

            /** Shared state. */
            companion object {
                /** The default. */
                val standard: Int = 0
            }
        }
        """, fileName: "Zoo.kt")
        let zoo = artifact.types.first
        #expect(zoo?.nestedTypes.first { $0.name == "Helper" }?.documentation == "An inner helper.")
        let companion = zoo?.nestedTypes.first { $0.name == "Companion" }
        #expect(companion?.documentation == "Shared state.")
        #expect(companion?.members.first?.documentation == "The default.")
    }

    @Test func aPlainCommentIsNotDocumentation() {
        let artifact = parser.parse(source: """
        // Just a line.
        class Zoo
        """, fileName: "Zoo.kt")
        #expect(artifact.types.first?.documentation == nil)
    }

    @Test func aBlankLineDetachesTheCommentsAboveIt() {
        let artifact = parser.parse(source: """
        /**
         * License header.
         */

        class Zoo

        /** Something else. */

        /** The keeper. */
        class Keeper
        """, fileName: "Zoo.kt")
        #expect(artifact.types.first { $0.name == "Zoo" }?.documentation == nil)
        #expect(artifact.types.first { $0.name == "Keeper" }?.documentation == "The keeper.")
    }
}
