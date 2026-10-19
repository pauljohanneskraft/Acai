import Testing
@testable import AcaiCore
@testable import AcaiJS

@Suite("JS Generic Variance Tests")
struct JSGenericVarianceTests {
    let typeScript = JSCodeParser()
    let javaScript = JSCodeParser(isTypeScript: false)

    // MARK: - The name, which is what regresses silently

    @Test func varianceModifiersLeaveTheParameterItsOwnName() {
        let source = """
        interface Producer<out T> {
            produce(): T;
        }

        interface Consumer<in T> {
            consume(item: T): void;
        }

        interface Invariant<in out T> {
            exchange(item: T): T;
        }
        """
        let artifact = typeScript.parse(source: source, fileName: "Variance.ts")

        for name in ["Producer", "Consumer", "Invariant"] {
            let type = artifact.types.first { $0.name == name }
            #expect(type?.genericParameters.map(\.name) == ["T"], "\(name) lost its parameter's name")
        }
    }

    @Test func nameSurvivesAConstraintAndADefault() {
        let source = """
        interface Sink<in T extends Error> {
            accept(value: T): void;
        }

        interface Defaulted<out T = string> {
            value(): T;
        }
        """
        let artifact = typeScript.parse(source: source, fileName: "Constrained.ts")

        let sink = artifact.types.first { $0.name == "Sink" }
        #expect(sink?.genericParameters.first?.name == "T")
        #expect(sink?.genericParameters.first?.constraints.first?.type.name == "Error")

        #expect(artifact.types.first { $0.name == "Defaulted" }?.genericParameters.first?.name == "T")
    }

    // MARK: - The variance itself

    @Test func varianceIsRecordedFromTheModifiers() {
        let source = """
        interface Producer<out T> { produce(): T; }
        interface Consumer<in T> { consume(item: T): void; }
        interface Invariant<in out T> { exchange(item: T): T; }
        interface Plain<T> { item(): T; }
        """
        let artifact = typeScript.parse(source: source, fileName: "Recorded.ts")

        func variance(_ type: String) -> Variance? {
            artifact.types.first { $0.name == type }?.genericParameters.first?.variance
        }
        #expect(variance("Producer") == .covariant)
        #expect(variance("Consumer") == .contravariant)
        #expect(variance("Invariant") == .invariant)
        // Nothing was declared, which is told apart from a declared invariance.
        #expect(variance("Plain") == nil)
    }

    @Test func varianceIsRecordedPerParameterInAList() {
        let source = "interface Pair<out T, in U, V> { exchange(value: U): T; }"
        let artifact = typeScript.parse(source: source, fileName: "List.ts")

        let parameters = artifact.types.first { $0.name == "Pair" }?.genericParameters
        #expect(parameters?.map(\.name) == ["T", "U", "V"])
        #expect(parameters?.map(\.variance) == [.covariant, .contravariant, nil])
    }

    @Test func varianceIsRecordedOnClassesAndMethods() {
        let source = """
        class Box<out T> {
            value?: T;
            map<in U>(transform: (value: U) => T): T | undefined { return this.value; }
        }
        """
        let artifact = typeScript.parse(source: source, fileName: "Box.ts")

        let box = artifact.types.first { $0.name == "Box" }
        #expect(box?.genericParameters.map(\.name) == ["T"])
        #expect(box?.genericParameters.first?.variance == .covariant)

        let map = box?.members.first { $0.name == "map" }
        #expect(map?.genericParameters.map(\.name) == ["U"])
        #expect(map?.genericParameters.first?.variance == .contravariant)
    }

    // MARK: - What must not be rewritten

    @Test func aParameterActuallyNamedOutKeepsThatName() {
        // `out` is not a reserved word: without a name after it, it *is* the name.
        let artifact = typeScript.parse(
            source: "interface Holder<out> { value(): out; }", fileName: "Named.ts")

        let holder = artifact.types.first { $0.name == "Holder" }
        #expect(holder?.genericParameters.map(\.name) == ["out"])
        #expect(holder?.genericParameters.first?.variance == nil)
    }

    @Test func surroundingCodeIsUnchangedByTheRewrite() {
        let source = """
        interface Producer<out T> {
            produce(): T;
        }

        class Factory implements Producer<string> {
            label = "in out";
            produce(): string { return this.label; }
        }
        """
        let artifact = typeScript.parse(source: source, fileName: "Surrounding.ts")

        let factory = artifact.types.first { $0.name == "Factory" }
        #expect(factory?.members.first { $0.name == "produce" }?.type?.name == "string")
        #expect(factory?.members.first { $0.name == "label" } != nil)
        // The rewrite is offset-preserving, so locations still point at the real lines.
        #expect(factory?.location?.line == 5)
        #expect(artifact.relationships.contains { $0.target.contains("Producer") })
    }

    @Test func aVarianceModifierIsNoLongerAParseError() {
        let artifact = typeScript.parse(
            source: "interface Producer<out T> { produce(): T; }", fileName: "Clean.ts")

        #expect(artifact.metadata.parseDiagnostics.isEmpty)
    }

    @Test func javaScriptIsLeftAlone() {
        let artifact = javaScript.parse(
            source: "const pick = (items, out) => items.filter((i, out) => i === out);",
            fileName: "pick.js")

        #expect(artifact.metadata.parseDiagnostics.isEmpty)
    }
}
