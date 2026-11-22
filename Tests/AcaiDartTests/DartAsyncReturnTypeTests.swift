import Testing
@testable import AcaiDart
@testable import AcaiCore

/// Dart has to declare `Future<T>` on an `async` body, where Swift and Kotlin write the payload and
/// mark the asynchrony with a keyword. The `.async` modifier is the shared fact, so the recorded
/// type is the payload.
///
/// Reaching the payload at all first needs Dart's return types to carry their generic arguments: the
/// grammar emits `Future` and `<int>` as siblings, which the signature readers used to drop.
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

    /// Dart writes a nullable generic argument's `?` as a sibling of the name it qualifies, so the
    /// payload's optionality is only preserved if that sibling is folded in.
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

    /// A `List<T>` payload keeps the arrayness that drives `*` multiplicity.
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

    /// A method that hands back a future without an `async` body really does return `Future`.
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

    /// An `async*` generator returns the `Stream` it declares, and a `sync*` one its `Iterable`:
    /// neither is a future of one element, so neither is unwrapped.
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

    /// A `Future` with no type argument names no payload, so it is reported as declared.
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

    /// An async getter is the same seam as an async method — its return type is read by a different
    /// signature reader, which had the same dropped-arguments bug.
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
