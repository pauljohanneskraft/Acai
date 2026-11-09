import Testing
@testable import AcaiDart
@testable import AcaiCore

@Suite("Dart: Generics Tests")
struct DartGenericsTests {
    let parser = DartCodeParser()

    @Test func genericClass() {
        let source = """
        class Box<T> {
            T value;
            Box(this.value);
        }
        """
        let artifact = parser.parse(source: source, fileName: "Box.dart")
        let box = artifact.types[0]
        #expect(box.genericParameters.count == 1)
        #expect(box.genericParameters[0].name == "T")
    }

    @Test func genericClassWithConstraint() {
        let source = """
        class Container<T extends Comparable> {
            T item;
        }
        """
        let artifact = parser.parse(source: source, fileName: "Container.dart")
        let container = artifact.types[0]
        #expect(container.genericParameters.count == 1)
        #expect(container.genericParameters[0].name == "T")
        #expect(container.genericParameters[0].constraints.map(\.type.name) == ["Comparable"])
    }

    /// A bound is a full type reference, not just a name: `Comparable<T>` has to keep its argument,
    /// or the bound reads as the raw `Comparable` and its relationship to `T` is lost.
    @Test func genericBoundKeepsItsTypeArguments() {
        let artifact = parser.parse(source: """
        class Container<T extends Comparable<T>, U extends num> {
            T item;
        }
        """, fileName: "Container.dart")
        let generics = artifact.types[0].genericParameters
        #expect(generics.map(\.name) == ["T", "U"])
        #expect(generics[0].constraints.count == 1)
        #expect(generics[0].constraints[0].kind == .superclass)
        #expect(generics[0].constraints[0].type.name == "Comparable")
        #expect(generics[0].constraints[0].type.genericArguments.map(\.name) == ["T"])
        #expect(generics[1].constraints.map(\.type.name) == ["num"])
    }

    /// A nested bound stays one reference rather than splitting into `Map` plus each argument.
    @Test func genericBoundWithNestedArguments() {
        let artifact = parser.parse(source: """
        class Cache<T extends Map<String, List<int>>> {
            T store;
        }
        """, fileName: "Cache.dart")
        let bound = artifact.types[0].genericParameters[0].constraints
        #expect(bound.count == 1)
        #expect(bound[0].type.name == "Map")
        #expect(bound[0].type.genericArguments.map(\.name) == ["String", "List", "int"])
    }

    @Test func multipleGenericParameters() {
        let source = """
        class Pair<K, V> {
            K key;
            V value;
        }
        """
        let artifact = parser.parse(source: source, fileName: "Pair.dart")
        let pair = artifact.types[0]
        #expect(pair.genericParameters.count == 2)
        #expect(pair.genericParameters[0].name == "K")
        #expect(pair.genericParameters[1].name == "V")
    }
}
