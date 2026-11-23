import Testing
@testable import AcaiJS
@testable import AcaiCore

@Suite("TypeScript async return types")
struct JSAsyncReturnTypeTests {
    let parser = JSCodeParser(isTypeScript: true)

    private func member(_ source: String, named name: String) -> Member? {
        parser.parse(source: source, fileName: "loader.ts").types.first?.members.first { $0.name == name }
    }

    @Test func asyncMethodReportsThePromisePayload() {
        let fetch = member(
            """
            class Loader {
                async fetch(): Promise<User> { return null }
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
                async load(): Promise<Map<string, User>> { return new Map() }
            }
            """,
            named: "load")
        #expect(load?.type?.name == "Map")
        #expect(load?.type?.genericArguments.map(\.name) == ["string", "User"])
    }

    @Test func promiseOfVoidBecomesVoid() {
        let flush = member(
            """
            class Loader {
                async flush(): Promise<void> {}
            }
            """,
            named: "flush")
        #expect(flush?.type?.name == "void")
    }

    @Test func arrayPayloadKeepsItsArrayness() {
        let all = member(
            """
            class Loader {
                async all(): Promise<User[]> { return [] }
            }
            """,
            named: "all")
        #expect(all?.type?.name == "User")
        #expect(all?.type?.isArray == true)
    }

    @Test func nonAsyncMethodReturningAPromiseKeepsTheWrapper() {
        let deferred = member(
            """
            class Loader {
                deferred(): Promise<User> { return Promise.resolve(null) }
            }
            """,
            named: "deferred")
        #expect(deferred?.modifiers.contains(.async) == false)
        #expect(deferred?.type?.name == "Promise")
        #expect(deferred?.type?.genericArguments.map(\.name) == ["User"])
    }

    @Test func interfaceRequirementKeepsItsPromise() {
        let fetch = parser
            .parse(source: "interface Api { fetch(): Promise<User> }", fileName: "api.ts")
            .types.first?.members.first
        #expect(fetch?.type?.name == "Promise")
    }

    @Test func bareUnparameterizedPromiseIsLeftAsDeclared() {
        let fetch = member(
            """
            class Loader {
                async fetch(): Promise { return null }
            }
            """,
            named: "fetch")
        #expect(fetch?.type?.name == "Promise")
    }

    @Test func asyncFreestandingFunctionReportsItsPayload() {
        let artifact = parser.parse(
            source: "export async function load(): Promise<User> { return null }", fileName: "load.ts")
        #expect(artifact.freestandingFunctions.first?.modifiers.contains(.async) == true)
        #expect(artifact.freestandingFunctions.first?.type == TypeReference(name: "User"))
    }

    @Test func asyncGeneratorKeepsItsSequenceType() {
        let stream = member(
            """
            class Loader {
                async *stream(): AsyncGenerator<User> {}
            }
            """,
            named: "stream")
        #expect(stream?.type?.name == "AsyncGenerator")
    }
}
