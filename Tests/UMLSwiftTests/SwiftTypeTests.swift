import Testing
@testable import UMLSwift
@testable import UMLCore

@Suite("Swift: Type Tests")
struct SwiftTypeTests {
    let parser = SwiftCodeParser()

    @Test func simpleClass() {
        let source = """
        public class Animal {
            var name: String
            private var age: Int
            init(name: String, age: Int) {
                self.name = name
                self.age = age
            }
            func speak() -> String {
                return name
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Animal.swift")
        #expect(artifact.types.count == 1)
        let animal = artifact.types[0]
        #expect(animal.name == "Animal")
        #expect(animal.kind == .class)
        #expect(animal.accessLevel == .public)
        #expect(animal.members.count == 4) // 2 props + init + method
    }

    @Test func structWithProtocolConformance() {
        let source = """
        struct Point: Equatable, Hashable {
            let x: Double
            let y: Double
        }
        """
        let artifact = parser.parse(source: source, fileName: "Point.swift")
        #expect(artifact.types.count == 1)
        let point = artifact.types[0]
        #expect(point.kind == .struct)
        #expect(point.inheritedTypes.count == 2)
        #expect(artifact.relationships.count == 2)
        #expect(artifact.relationships.allSatisfy { $0.kind == .conformance })
    }

    @Test func enumWithCases() {
        let source = """
        enum Direction: String {
            case north = "N"
            case south = "S"
            case east = "E"
            case west = "W"
        }
        """
        let artifact = parser.parse(source: source, fileName: "Direction.swift")
        #expect(artifact.types.count == 1)
        let dir = artifact.types[0]
        #expect(dir.kind == .enum)
        #expect(dir.enumCases.count == 4)
        #expect(dir.enumCases[0].name == "north")
        #expect(dir.enumCases[0].rawValue == "\"N\"")
    }

    @Test func protocolDeclaration() {
        let source = """
        public protocol Repository {
            associatedtype Entity
            func findAll() -> [Entity]
            func save(_ entity: Entity)
        }
        """
        let artifact = parser.parse(source: source, fileName: "Repository.swift")
        #expect(artifact.types.count == 1)
        let repo = artifact.types[0]
        #expect(repo.kind == .protocol)
        #expect(repo.accessLevel == .public)
        #expect(repo.members.count == 2) // findAll + save
    }

    @Test func extensionDeclaration() {
        let source = """
        extension String: CustomStringConvertible {
            func reversed() -> String { String(self.reversed()) }
        }
        """
        let artifact = parser.parse(source: source, fileName: "StringExt.swift")
        #expect(artifact.types.count == 1)
        let ext = artifact.types[0]
        #expect(ext.kind == .extension)
        #expect(ext.extensionOf == "String")
        #expect(ext.members.count == 1)
        #expect(ext.inheritedTypes.count == 1)
    }

    @Test func genericClass() {
        let source = """
        class Box<T: Equatable> {
            var value: T
            init(value: T) { self.value = value }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Box.swift")
        let box = artifact.types[0]
        #expect(box.genericParameters.count == 1)
        #expect(box.genericParameters[0].name == "T")
        #expect(box.genericParameters[0].constraints.count == 1)
    }

    @Test func nestedTypes() {
        let source = """
        class Outer {
            struct Inner {
                var value: Int
            }
            enum Status { case active, inactive }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Nested.swift")
        #expect(artifact.types.count == 1)
        let outer = artifact.types[0]
        #expect(outer.nestedTypes.count == 2)
        #expect(outer.nestedTypes[0].kind == .struct)
        #expect(outer.nestedTypes[1].kind == .enum)
    }

    @Test func inheritance() {
        let source = """
        class Dog: Animal, Hashable, CustomStringConvertible {
            var breed: String = ""
        }
        """
        let artifact = parser.parse(source: source, fileName: "Dog.swift")
        #expect(artifact.relationships.count == 3)
        #expect(artifact.relationships[0].kind == .inheritance)
        #expect(artifact.relationships[0].target == "Animal")
        #expect(artifact.relationships[1].kind == .conformance)
        #expect(artifact.relationships[2].kind == .conformance)
    }

    @Test func typeAlias() {
        let source = """
        public typealias StringMap = Dictionary<String, String>
        """
        let artifact = parser.parse(source: source, fileName: "Aliases.swift")
        #expect(artifact.types.count == 1)
        #expect(artifact.types[0].kind == .typeAlias)
        #expect(artifact.types[0].name == "StringMap")
    }

    @Test func actorDeclaration() {
        let source = """
        actor DataStore {
            var items: [String] = []
            func add(_ item: String) { items.append(item) }
        }
        """
        let artifact = parser.parse(source: source, fileName: "DataStore.swift")
        #expect(artifact.types.count == 1)
        #expect(artifact.types[0].name == "DataStore")
        #expect(artifact.types[0].annotations.contains("@actor"))
        #expect(artifact.types[0].members.count == 2) // items + add
    }

    @Test func enumWithAssociatedValues() {
        let source = """
        enum Result<T, E> {
            case success(T)
            case failure(E)
            case pending(retryCount: Int)
        }
        """
        let artifact = parser.parse(source: source, fileName: "Result.swift")
        #expect(artifact.types.count == 1)
        let result = artifact.types[0]
        #expect(result.kind == .enum)
        #expect(result.enumCases.count == 3)
        #expect(result.enumCases[0].name == "success")
        #expect(result.enumCases[1].name == "failure")
        #expect(result.enumCases[2].name == "pending")
        #expect(result.genericParameters.count == 2)
    }

    @Test func compositionTypes() {
        let source = """
        struct Model: Codable & Hashable & Identifiable {
            var id: String
        }
        """
        let artifact = parser.parse(source: source, fileName: "Composition.swift")
        let model = artifact.types[0]
        #expect(model.inheritedTypes.count == 3)
        #expect(model.inheritedTypes.map(\.name) == ["Codable", "Hashable", "Identifiable"])
        #expect(artifact.relationships.count == 3)
        #expect(artifact.relationships.allSatisfy { $0.kind == .conformance })
    }

    @Test func compositionTypesEquivalentToCommaList() {
        let ampersand = parser.parse(source: "struct A: B & C {}", fileName: "A.swift")
        let commaList = parser.parse(source: "struct A: B, C {}", fileName: "A.swift")

        #expect(ampersand.types[0].inheritedTypes.count == 2)
        #expect(commaList.types[0].inheritedTypes.count == 2)
        #expect(ampersand.types[0].inheritedTypes.map(\.name) == commaList.types[0].inheritedTypes.map(\.name))
        #expect(ampersand.relationships.count == commaList.relationships.count)
        for (lhs, rhs) in zip(ampersand.relationships, commaList.relationships) {
            #expect(lhs.kind == rhs.kind)
            #expect(lhs.target == rhs.target)
        }
    }

    @Test func compositionInGenericArgumentIsNotFlattened() {
        let source = """
        class Container {
            var value: Dictionary<String & CustomStringConvertible, Int>
        }
        """
        let artifact = parser.parse(source: source, fileName: "Container.swift")
        let container = artifact.types[0]
        let valueMember = container.members.first { $0.name == "value" }
        #expect(valueMember != nil)
        // The generic type should have exactly 2 arguments, not 3.
        // `String & CustomStringConvertible` is a single composition type, not two separate types.
        let typeRef = valueMember?.type
        #expect(typeRef?.genericArguments.count == 2)
        #expect(typeRef?.genericArguments[0].name == "String & CustomStringConvertible")
        // The composition's components are stored as nested genericArguments
        // so the enricher can discover them for relationship inference.
        #expect(typeRef?.genericArguments[0].genericArguments.count == 2)
        #expect(typeRef?.genericArguments[0].genericArguments[0].name == "String")
        #expect(typeRef?.genericArguments[0].genericArguments[1].name == "CustomStringConvertible")
        #expect(typeRef?.genericArguments[1].name == "Int")
    }

    @Test func finalClass() {
        let source = """
        final class Singleton {
            static let shared = Singleton()
        }
        """
        let artifact = parser.parse(source: source, fileName: "Final.swift")
        let singleton = artifact.types[0]
        #expect(singleton.modifiers.contains(.final))
    }
}
