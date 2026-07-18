import Testing
@testable import AcaiJVM
@testable import AcaiCore

@Suite("Java: Access Levels")
struct JavaAccessLevelTests {
    let parser = JavaCodeParser()

    @Test func defaultAccessIsPackagePrivate() {
        // A type and member with no explicit modifier are package-private in Java; the parser
        // resolves that default so the engine never sees a nil access level.
        let source = """
        class Helper {
            int value;
        }
        """
        let artifact = parser.parse(source: source, fileName: "Helper.java")
        let helper = artifact.types[0]
        #expect(helper.accessLevel == .packagePrivate)
        #expect(helper.members.first { $0.name == "value" }?.accessLevel == .packagePrivate)
    }
}
