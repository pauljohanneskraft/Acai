import Testing
@testable import AcaiCFamily
@testable import AcaiCore

/// The `#ifdef __cplusplus` / `extern "C" {` / `#endif` header guard splits a brace pair across two
/// preprocessor branches, which Tree-sitter cannot balance. `CPlusPlusLinkageGuards` blanks the
/// guards before parsing so the header reports neither a missing `}` nor a truncated declaration
/// list, in either dialect.
@Suite("C-family: extern \"C\" linkage guards")
struct ExternCLinkageGuardTests {

    /// The shape found in nearly every C library header, including this repo's vendored
    /// `tree_sitter/alloc.h`, `array.h` and `parser.h`.
    let guardedHeader = """
    #ifndef ACAI_SHAPES_H_
    #define ACAI_SHAPES_H_

    #ifdef __cplusplus
    extern "C" {
    #endif

    #include <stdbool.h>

    struct Point {
        int x;
        int y;
    };

    int point_distance(struct Point a, struct Point b);

    bool point_equal(struct Point a, struct Point b);

    #ifdef __cplusplus
    }
    #endif

    #endif // ACAI_SHAPES_H_
    """

    @Test func guardedHeaderParsesCleanlyAsC() {
        let artifact = CCodeParser().parse(source: guardedHeader, fileName: "shapes.h")
        #expect(artifact.metadata.sourceLanguage == .c)
        #expect(artifact.metadata.parseDiagnostics.isEmpty)
        #expect(artifact.types.map(\.name) == ["Point"])
        #expect(artifact.types.first?.members.map(\.name).sorted() == ["x", "y"])
        #expect(
            artifact.freestandingFunctions.map(\.name).sorted() == ["point_distance", "point_equal"]
        )
    }

    @Test func guardedHeaderParsesCleanlyAsCpp() {
        let artifact = CppCodeParser().parse(source: guardedHeader, fileName: "shapes.hpp")
        #expect(artifact.metadata.sourceLanguage == .cpp)
        #expect(artifact.metadata.parseDiagnostics.isEmpty)
        #expect(artifact.types.map(\.name) == ["Point"])
        #expect(
            artifact.freestandingFunctions.map(\.name).sorted() == ["point_distance", "point_equal"]
        )
    }

    /// Blanking keeps the file's length and every newline in place, so a declaration below a guard
    /// still reports the line it is written on.
    @Test func locationsSurviveBlanking() {
        let artifact = CCodeParser().parse(source: guardedHeader, fileName: "shapes.h")
        #expect(artifact.types.first?.location?.line == 10)
    }

    @Test func definedSpellingsAreRecognised() {
        for condition in ["#ifdef __cplusplus", "#if defined(__cplusplus)", "#if defined __cplusplus"] {
            let source = """
            \(condition)
            extern "C" {
            #endif
            void ping(void);
            \(condition)
            }  /* extern "C" */
            #endif  // __cplusplus
            """
            let artifact = CCodeParser().parse(source: source, fileName: "ping.h")
            #expect(artifact.metadata.parseDiagnostics.isEmpty, "\(condition)")
            #expect(artifact.freestandingFunctions.map(\.name) == ["ping"], "\(condition)")
        }
    }

    /// A guard holding a real declaration is not a linkage guard and must be left to the grammar.
    @Test func guardAroundRealDeclarationsIsKept() {
        let source = """
        #ifdef __cplusplus
        void cpp_only(int value);
        #endif
        void always_there(void);
        """
        let artifact = CCodeParser().parse(source: source, fileName: "mixed.h")
        #expect(artifact.freestandingFunctions.map(\.name).sorted() == ["always_there", "cpp_only"])
    }

    @Test func blankingPreservesLengthAndLineBreaks() {
        let blanked = CPlusPlusLinkageGuards(source: guardedHeader).neutralized
        #expect(blanked.count == guardedHeader.count)
        #expect(
            blanked.split(separator: "\n", omittingEmptySubsequences: false).count
                == guardedHeader.split(separator: "\n", omittingEmptySubsequences: false).count
        )
        #expect(!blanked.contains("extern"))
        #expect(blanked.contains("#ifndef ACAI_SHAPES_H_"))
    }

    @Test func unrelatedConditionalsAreUntouched() {
        let source = """
        #ifdef _WIN32
        extern "C" {
        #endif
        """
        #expect(CPlusPlusLinkageGuards(source: source).neutralized == source)
    }
}
