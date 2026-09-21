import Testing
@testable import AcaiDart
@testable import AcaiCore

@Suite("Dart: Modifier Tests")
struct DartModifierTests {
    let parser = DartCodeParser()

    /// `@override` maps to the `.override` modifier and a body-less method is marked `.abstract`, so the
    /// dead-code scan exempts both the requirement and its override as reachable-by-contract.
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

    /// `async`, `async*` and `sync*` body markers all carry the `.async` modifier; a synchronous
    /// method carries none of it.
    @Test func asyncBodyMarkersMapToAsyncModifier() {
        let source = """
        class Repo {
            Future<void> load() async {
                await fetch();
            }
            Stream<int> counts() async* {
                yield 1;
            }
            Iterable<int> values() sync* {
                yield 1;
            }
            void plain() {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "repo.dart")
        let repo = artifact.types.first { $0.name == "Repo" }
        #expect(repo?.members.first { $0.name == "load" }?.modifiers.contains(.async) == true)
        #expect(repo?.members.first { $0.name == "counts" }?.modifiers.contains(.async) == true)
        #expect(repo?.members.first { $0.name == "values" }?.modifiers.contains(.async) == true)
        #expect(repo?.members.first { $0.name == "plain" }?.modifiers.contains(.async) == false)
    }

    /// A top-level `async` function carries the same modifier as an async method.
    @Test func asyncFreestandingFunctionMapsToAsyncModifier() {
        let source = """
        Future<String> fetchName() async {
            return 'name';
        }

        String plainName() {
            return 'name';
        }
        """
        let artifact = parser.parse(source: source, fileName: "utils.dart")
        let fetchName = artifact.freestandingFunctions.first { $0.name == "fetchName" }
        let plainName = artifact.freestandingFunctions.first { $0.name == "plainName" }
        #expect(fetchName?.modifiers.contains(.async) == true)
        #expect(plainName?.modifiers.contains(.async) == false)
    }
}
