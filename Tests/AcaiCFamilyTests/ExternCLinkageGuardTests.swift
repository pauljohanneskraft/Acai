import Foundation
import Testing
@testable import AcaiCFamily
@testable import AcaiCore

@Suite("C-family: extern \"C\" linkage guards")
struct ExternCLinkageGuardTests {

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

    /// `\r\n` is one grapheme cluster, so it never equals `"\n"`.
    @Test func carriageReturnLineEndingsAreHandled() {
        let source = guardedHeader.replacingOccurrences(of: "\n", with: "\r\n")
        let artifact = CCodeParser().parse(source: source, fileName: "shapes.h")
        #expect(artifact.metadata.parseDiagnostics.isEmpty)
        #expect(artifact.types.map(\.name) == ["Point"])
        #expect(artifact.types.first?.location?.line == 10)
    }

    /// `Node.text(in:)` indexes the source by UTF-16 offset.
    @Test func blankingIsLengthExactAcrossNonASCII() {
        let source = """
        #ifdef __cplusplus
        extern "C" {
        #endif  // naïve — 🎉
        void ping(void);
        #ifdef __cplusplus
        }  /* naïve — 🎉 */
        #endif
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

    @Test func unpairedOpeningGuardStillReportsTheMissingBrace() {
        let source = """
        #ifdef __cplusplus
        extern "C" {
        #endif
        void ping(void);
        """
        #expect(CPlusPlusLinkageGuards(source: source).neutralized == source)
        let artifact = CppCodeParser().parse(source: source, fileName: "ping.hpp")
        #expect(!artifact.metadata.parseDiagnostics.isEmpty)
    }

    @Test func unpairedClosingGuardIsKept() {
        let source = """
        void ping(void);
        #ifdef __cplusplus
        }
        #endif
        """
        #expect(CPlusPlusLinkageGuards(source: source).neutralized == source)
    }

    @Test func unbalancedConditionalStillReportsADiagnostic() {
        let source = """
        #ifdef FEATURE
        void ping(void);
        """
        let artifact = CCodeParser().parse(source: source, fileName: "ping.h")
        #expect(!artifact.metadata.parseDiagnostics.isEmpty)
    }
}
