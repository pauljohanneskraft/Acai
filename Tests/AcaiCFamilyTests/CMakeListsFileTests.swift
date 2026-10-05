import Testing
@testable import AcaiCFamily

/// `add_subdirectory()` is the one CMake command that composes a project from parts, so it is read
/// from the listfile's text: its first argument alone, in either case, past comments and quotes.
@Suite("C-family: CMakeLists.txt add_subdirectory()")
struct CMakeListsFileTests {

    private func subdirectories(_ source: String) -> [CMakeListsFile.Subdirectory] {
        CMakeListsFile(source: source).subdirectories
    }

    @Test func readsEveryDeclaredDirectoryInOrder() {
        let source = """
        project(Composed)
        add_subdirectory(core)
        add_subdirectory(ui)
        """
        #expect(subdirectories(source) == [.literal("core"), .literal("ui")])
    }

    /// `add_subdirectory(<dir> <binary_dir>)`: only the first argument is a source directory.
    @Test func readsOnlyTheFirstArgument() {
        #expect(subdirectories("add_subdirectory(core build/core)") == [.literal("core")])
    }

    /// `EXCLUDE_FROM_ALL` is about the default build target, not about whether the code exists.
    @Test func excludeFromAllIsStillADirectory() {
        #expect(subdirectories("add_subdirectory(vendor EXCLUDE_FROM_ALL)") == [.literal("vendor")])
    }

    @Test func readsAQuotedDirectoryWithoutItsQuotes() {
        #expect(subdirectories("add_subdirectory(\"my core\")") == [.literal("my core")])
    }

    @Test func commandNamesAreCaseInsensitiveAndMayBeSpacedFromTheirParenthesis() {
        #expect(subdirectories("ADD_SUBDIRECTORY (core)") == [.literal("core")])
    }

    @Test func aLongerIdentifierIsNotTheCommand() {
        #expect(subdirectories("my_add_subdirectory(core)\nadd_subdirectory_once(ui)").isEmpty)
    }

    @Test func aCommentedOutCallNamesNothing() {
        let source = """
        # add_subdirectory(core)
        #[[
        add_subdirectory(ui)
        ]]
        add_subdirectory(real)
        """
        #expect(subdirectories(source) == [.literal("real")])
    }

    @Test func anEmptyCallNamesNothing() {
        #expect(subdirectories("add_subdirectory()").isEmpty)
    }

    /// Every form CMake expands at configure time is reported as computed, since the directory it
    /// names cannot be known from the text.
    @Test func variablesEnvironmentLookupsAndGeneratorExpressionsAreComputed() {
        #expect(subdirectories("add_subdirectory(${MODULE})") == [.computed(argument: "${MODULE}")])
        #expect(subdirectories("add_subdirectory($ENV{EXTRA})") == [.computed(argument: "$ENV{EXTRA}")])
        #expect(
            subdirectories("add_subdirectory($<CONFIG>)") == [.computed(argument: "$<CONFIG>")])
    }
}
