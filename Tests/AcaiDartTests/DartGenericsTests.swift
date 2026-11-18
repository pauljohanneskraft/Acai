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

    @Test func genericBoundKeepsItsTypeArguments() throws {
        let artifact = parser.parse(source: """
        class Container<T extends Comparable<T>, U extends num> {
            T item;
        }
        """, fileName: "Container.dart")
        let generics = try #require(artifact.types.first).genericParameters
        #expect(generics.map(\.name) == ["T", "U"])
        try #require(generics.count == 2)
        let bound = try #require(generics[0].constraints.first)
        #expect(generics[0].constraints.count == 1)
        #expect(bound.kind == .superclass)
        #expect(bound.type.name == "Comparable")
        #expect(bound.type.genericArguments.map(\.name) == ["T"])
        #expect(generics[1].constraints.map(\.type.name) == ["num"])
    }

    @Test func genericBoundWithNestedArguments() throws {
        let artifact = parser.parse(source: """
        class Cache<T extends Map<String, List<int>>> {
            T store;
        }
        """, fileName: "Cache.dart")
        let parameter = try #require(artifact.types.first?.genericParameters.first)
        #expect(parameter.constraints.count == 1)
        let bound = try #require(parameter.constraints.first)
        #expect(bound.type.name == "Map")
        #expect(bound.type.genericArguments.map(\.name) == ["String", "List"])
        let list = try #require(bound.type.genericArguments.last)
        #expect(list.isArray)
        #expect(list.genericArguments.map(\.name) == ["int"])
    }

    @Test func fieldTypeKeepsNestedArguments() throws {
        let artifact = parser.parse(source: """
        class Cache {
            Map<String, List<int>> store;
        }
        """, fileName: "Cache.dart")
        let type = try #require(artifact.types.first?.members.first?.type)
        #expect(type.name == "Map")
        #expect(type.genericArguments.map(\.name) == ["String", "List"])
        #expect(type.genericArguments.last?.genericArguments.map(\.name) == ["int"])
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
