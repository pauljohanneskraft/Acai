import Testing
@testable import AcaiDart
@testable import AcaiCore

@Suite("Dart async return types")
struct DartAsyncReturnTypeTests {
    let parser = DartCodeParser()

    private func member(_ source: String, named name: String) -> Member? {
        parser.parse(source: source, fileName: "loader.dart").types.first?.members.first { $0.name == name }
    }

    @Test func asyncMethodReportsTheFuturePayload() {
        let fetch = member(
            """
            class Loader {
              Future<User> fetch() async => null;
            }
            """,
            named: "fetch")
        #expect(fetch?.modifiers.contains(.async) == true)
        #expect(fetch?.type == TypeReference(name: "User"))
    }

    @Test func nestedGenericPayloadSurvivesUnwrapping() {
        let load = member(
            """
            class Loader {
              Future<Map<String, User>> load() async => {};
            }
            """,
            named: "load")
        #expect(load?.type?.name == "Map")
        #expect(load?.type?.genericArguments.map(\.name) == ["String", "User"])
    }

    @Test func futureOrIsUnwrappedTheSameWay() {
        let maybe = member(
            """
            class Loader {
              FutureOr<User> maybe() async => null;
            }
            """,
            named: "maybe")
        #expect(maybe?.type == TypeReference(name: "User"))
    }

    @Test func futureOfVoidBecomesVoid() {
        let flush = member(
            """
            class Loader {
              Future<void> flush() async {}
            }
            """,
            named: "flush")
        #expect(flush?.type?.name == "void")
    }

    @Test func nullablePayloadStaysOptional() {
        let find = member(
            """
            class Loader {
              Future<User?> find() async => null;
            }
            """,
            named: "find")
        #expect(find?.type?.name == "User")
        #expect(find?.type?.isOptional == true)
    }

    @Test func listPayloadKeepsItsArrayness() {
        let all = member(
            """
            class Loader {
              Future<List<User>> all() async => [];
            }
            """,
            named: "all")
        #expect(all?.type?.name == "List")
        #expect(all?.type?.isArray == true)
        #expect(all?.type?.genericArguments.map(\.name) == ["User"])
    }

    @Test func nonAsyncMethodReturningAFutureKeepsTheWrapper() {
        let deferred = member(
            """
            class Loader {
              Future<User> deferred() => Future.value(null);
            }
            """,
            named: "deferred")
        #expect(deferred?.modifiers.contains(.async) == false)
        #expect(deferred?.type?.name == "Future")
        #expect(deferred?.type?.genericArguments.map(\.name) == ["User"])
    }

    @Test func generatorBodiesKeepTheirSequenceTypes() {
        let source = """
        class Loader {
          Stream<User> watch() async* {}
          Iterable<User> each() sync* {}
        }
        """
        #expect(member(source, named: "watch")?.type?.name == "Stream")
        #expect(member(source, named: "each")?.type?.name == "Iterable")
    }

    @Test func bareUnparameterizedFutureIsLeftAsDeclared() {
        let fetch = member(
            """
            class Loader {
              Future fetch() async {}
            }
            """,
            named: "fetch")
        #expect(fetch?.type?.name == "Future")
    }

    @Test func asyncGetterReportsItsPayload() {
        let current = member(
            """
            class Loader {
              Future<User> get current async => null;
            }
            """,
            named: "current")
        #expect(current?.isComputed == true)
        #expect(current?.type == TypeReference(name: "User"))
    }

    @Test func asyncTopLevelFunctionReportsItsPayload() {
        let artifact = parser.parse(
            source: "Future<User> load() async => null;", fileName: "load.dart")
        #expect(artifact.freestandingFunctions.first?.modifiers.contains(.async) == true)
        #expect(artifact.freestandingFunctions.first?.type == TypeReference(name: "User"))
    }
}
