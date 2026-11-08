import Foundation
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
        #expect(blanked.utf16.count == guardedHeader.utf16.count)
        #expect(
            blanked.split(separator: "\n", omittingEmptySubsequences: false).count
                == guardedHeader.split(separator: "\n", omittingEmptySubsequences: false).count
        )
        #expect(!blanked.contains("extern"))
        #expect(blanked.contains("#ifndef ACAI_SHAPES_H_"))
    }

    /// A Windows-authored header's line terminator is a single `\r\n` grapheme cluster, which never
    /// equals `"\n"` — so the guards have to be found without comparing against a bare newline.
    @Test func carriageReturnLineEndingsAreHandled() {
        let source = guardedHeader.replacingOccurrences(of: "\n", with: "\r\n")
        let artifact = CCodeParser().parse(source: source, fileName: "shapes.h")
        #expect(artifact.metadata.parseDiagnostics.isEmpty)
        #expect(artifact.types.map(\.name) == ["Point"])
        #expect(artifact.types.first?.location?.line == 10)
    }

    /// `Node.text(in:)` indexes the source by UTF-16 offset, so a guard carrying a non-ASCII
    /// comment is blanked to the same UTF-16 width rather than one space per character. A space is
    /// one UTF-16 unit and one byte, so UTF-16 and UTF-8 widths cannot both be held; UTF-16 is the
    /// one every text accessor here counts in.
    @Test func blankingIsLengthExactAcrossNonASCII() {
        let source = """
        #ifdef __cplusplus
        extern "C" {
        #endif  // naïve — 🎉
        void ping(void);
        """
        let blanked = CPlusPlusLinkageGuards(source: source).neutralized
        #expect(blanked.utf16.count == source.utf16.count)
        let artifact = CCodeParser().parse(source: source, fileName: "ping.h")
        #expect(artifact.freestandingFunctions.map(\.name) == ["ping"])
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
