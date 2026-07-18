import Testing
@testable import AcaiDart
@testable import AcaiCore

@Suite("Dart: Modifier Tests")
struct DartModifierTests {
    let parser = DartCodeParser()

    /// `@override` maps to the `.override` modifier and a body-less method is marked `.abstract`, so the
    /// dead-code scan exempts both the requirement and its override as reachable-by-contract (RC3).
    @Test func overrideAnnotationAndBodylessAbstractMapToModifiers() {
        let source = """
        abstract class Base {
            void hook();
        }
        class Impl extends Base {
            @override
            void hook() {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "hooks.dart")
        let baseHook = artifact.types.first { $0.name == "Base" }?.members.first { $0.name == "hook" }
        let implHook = artifact.types.first { $0.name == "Impl" }?.members.first { $0.name == "hook" }
        #expect(baseHook?.modifiers.contains(.abstract) == true)
        #expect(implHook?.modifiers.contains(.override) == true)
    }
}
