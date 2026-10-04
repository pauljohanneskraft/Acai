import Testing
@testable import AcaiCFamily
@testable import AcaiCore

@Suite("C/C++: Documentation Comments")
struct CFamilyDocumentationTests {
    private let cParser = CCodeParser()
    private let cppParser = CppCodeParser()

    @Test func doxygenBlockOnARecordAndItsFields() {
        let artifact = cParser.parse(source: """
        /**
         * The zoo.
         *
         * Holds animals.
         */
        struct Zoo {
            /** The name. */
            char *name;
            /* Not documentation. */
            int count;
        };
        """, fileName: "zoo.c")
        let zoo = artifact.types.first
        #expect(zoo?.documentation == "The zoo.\n\nHolds animals.")
        #expect(zoo?.members.first { $0.name == "name" }?.documentation == "The name.")
        #expect(zoo?.members.first { $0.name == "count" }?.documentation == nil)
    }

    @Test func allFourDoxygenMarkersAreRecognised() {
        let artifact = cParser.parse(source: """
        /// A dog.
        struct Dog {};
        //! A cat.
        struct Cat {};
        /*! A fish. */
        struct Fish {};
        /** A bird. */
        struct Bird {};
        """, fileName: "animals.c")
        #expect(artifact.types.first { $0.name == "Dog" }?.documentation == "A dog.")
        #expect(artifact.types.first { $0.name == "Cat" }?.documentation == "A cat.")
        #expect(artifact.types.first { $0.name == "Fish" }?.documentation == "A fish.")
        #expect(artifact.types.first { $0.name == "Bird" }?.documentation == "A bird.")
    }

    @Test func enumsTypedefsAndFreeFunctionsAreDocumented() {
        let artifact = cParser.parse(source: """
        /** Species. */
        enum Species {
            /** A dog. */
            DOG
        };

        /** A handle. */
        typedef unsigned int Handle;

        /** Feeds everyone. */
        void feed(struct Zoo *zoo) {}
        """, fileName: "zoo.c")
        let species = artifact.types.first { $0.name == "Species" }
        #expect(species?.documentation == "Species.")
        #expect(species?.enumCases.first?.documentation == "A dog.")
        #expect(artifact.types.first { $0.name == "Handle" }?.documentation == "A handle.")
        #expect(artifact.freestandingFunctions.first { $0.name == "feed" }?.documentation == "Feeds everyone.")
    }

    @Test func aCppClassItsMembersAndANestedTypeAreDocumented() {
        let artifact = cppParser.parse(source: """
        /** The zoo. */
        class Zoo {
        public:
            /** The name. */
            std::string name;
            /** Feeds everyone. */
            void feed();
            /** An inner helper. */
            struct Helper {
                /** How many. */
                int count;
            };
        };
        """, fileName: "zoo.cpp")
        let zoo = artifact.types.first { $0.name == "Zoo" }
        #expect(zoo?.documentation == "The zoo.")
        #expect(zoo?.members.first { $0.name == "name" }?.documentation == "The name.")
        #expect(zoo?.members.first { $0.name == "feed" }?.documentation == "Feeds everyone.")
        let helper = zoo?.nestedTypes.first { $0.name == "Helper" }
        #expect(helper?.documentation == "An inner helper.")
        #expect(helper?.members.first?.documentation == "How many.")
    }

    @Test func aTemplateAndANamespacedTypeAreDocumented() {
        let artifact = cppParser.parse(source: """
        namespace zoo {
            /** A box. */
            template <typename T>
            class Box {};
        }
        """, fileName: "box.cpp")
        #expect(artifact.types.first { $0.name == "Box" }?.documentation == "A box.")
    }

    @Test func aDeclarationInsideAnIncludeGuardKeepsItsOwnDocumentation() {
        let artifact = cParser.parse(source: """
        #ifndef ZOO_H
        #define ZOO_H

        /** The zoo. */
        struct Zoo {};

        #endif
        """, fileName: "zoo.h")
        #expect(artifact.types.first { $0.name == "Zoo" }?.documentation == "The zoo.")
    }

    @Test func aPlainCommentIsNotDocumentation() {
        let artifact = cParser.parse(source: """
        // Just a line.
        struct Zoo {};
        """, fileName: "zoo.c")
        #expect(artifact.types.first?.documentation == nil)
    }
}
