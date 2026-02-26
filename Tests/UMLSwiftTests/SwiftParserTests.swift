import Testing
@testable import UMLSwift
@testable import UMLCore

@Suite("Swift Parser Tests")
struct SwiftParserTests {
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

    @Test func accessLevels() {
        let source = """
        public class MyClass {
            public var a: Int = 0
            internal var b: Int = 0
            fileprivate var c: Int = 0
            private var d: Int = 0
        }
        """
        let artifact = parser.parse(source: source, fileName: "Access.swift")
        let cls = artifact.types[0]
        #expect(cls.members.count == 4)
        #expect(cls.members[0].accessLevel == .public)
        #expect(cls.members[1].accessLevel == .internal)
        #expect(cls.members[2].accessLevel == .filePrivate)
        #expect(cls.members[3].accessLevel == .private)
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

    @Test func freestandingFunction() {
        let source = """
        func helper(x: Int, y: Int) -> Int {
            return x + y
        }
        """
        let artifact = parser.parse(source: source, fileName: "Helpers.swift")
        #expect(artifact.types.isEmpty)
        #expect(artifact.freestandingFunctions.count == 1)
        #expect(artifact.freestandingFunctions[0].name == "helper")
        #expect(artifact.freestandingFunctions[0].parameters.count == 2)
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

    @Test func asyncThrowsFunction() {
        let source = """
        class Service {
            func fetch(url: URL) async throws -> Data { Data() }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Service.swift")
        let method = artifact.types[0].members[0]
        #expect(method.modifiers.contains(.async))
        #expect(method.modifiers.contains(.throws))
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

    @Test func computedProperty() {
        let source = """
        struct Circle {
            var radius: Double
            var diameter: Double { radius * 2 }
            var area: Double {
                get { .pi * radius * radius }
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Circle.swift")
        let circle = artifact.types[0]
        #expect(circle.members.count == 3)
        #expect(circle.members[0].isComputed == false)
        #expect(circle.members[1].isComputed == true)
        #expect(circle.members[2].isComputed == true)
    }

    @Test func multipleGenericConstraints() {
        let source = """
        func process<T: Codable & Hashable>(item: T) -> String {
            return String(describing: item)
        }
        """
        let artifact = parser.parse(source: source, fileName: "Generic.swift")
        #expect(artifact.freestandingFunctions.count == 1)
        let func_ = artifact.freestandingFunctions[0]
        #expect(func_.genericParameters.count == 1)
        #expect(func_.genericParameters[0].constraints.count >= 1)
    }

    @Test func whereClauseGeneric() {
        let source = """
        func combine<S: Sequence>(items: S) -> [S.Element] where S.Element: Comparable {
            return items.sorted()
        }
        """
        let artifact = parser.parse(source: source, fileName: "Where.swift")
        #expect(artifact.freestandingFunctions.count == 1)
        let func_ = artifact.freestandingFunctions[0]
        #expect(func_.genericParameters.count == 1)
    }

    @Test func attributesAndAnnotations() {
        let source = """
        struct User: Codable {
            @Published var name: String
            @State private var isActive: Bool
            var id: UUID
        }
        """
        let artifact = parser.parse(source: source, fileName: "User.swift")
        let user = artifact.types[0]
        #expect(user.members.count == 3)
        #expect(user.members[0].annotations.contains("@Published"))
        #expect(user.members[1].annotations.contains("@State"))
    }

    @Test func tupleTypes() {
        let source = """
        struct Coordinate {
            var point: (x: Double, y: Double)
            func swap(_ pair: (Int, String)) -> (String, Int) {
                return (pair.1, pair.0)
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Tuple.swift")
        let coord = artifact.types[0]
        #expect(coord.members.count == 2)
        #expect(coord.members[0].type?.name.contains("(") == true)
    }

    @Test func closureTypes() {
        let source = """
        class Handler {
            var callback: ((String) -> Void)?
            func process(with handler: (Int, String) throws -> Bool) {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "Closure.swift")
        let handler = artifact.types[0]
        #expect(handler.members.count == 2)
    }

    @Test func opaqueReturnTypes() {
        let source = """
        protocol Shape {}
        struct SomeShape: Shape {}
        func makeShape() -> some Shape {
            return SomeShape()
        }
        """
        let artifact = parser.parse(source: source, fileName: "Opaque.swift")
        #expect(artifact.types.count == 2)
        #expect(artifact.freestandingFunctions.count == 1)
    }

    @Test func callSiteTracking() {
        let source = """
        class Service {
            var helper: Helper
            func execute() {
                helper.process()
                self.helper.validate()
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "CallSite.swift")
        let service = artifact.types[0]
        let executeMethod = service.members.first { $0.name == "execute" }
        #expect(executeMethod?.callSites.count == 2)
        #expect(executeMethod?.callSites[0].receiverType == "Helper")
        #expect(executeMethod?.callSites[0].methodName == "process")
        #expect(executeMethod?.callSites[1].receiverType == "Helper")
        #expect(executeMethod?.callSites[1].methodName == "validate")
    }

    @Test func staticAndClassMembers() {
        let source = """
        class MyClass {
            static var shared: MyClass = MyClass()
            class func create() -> MyClass { MyClass() }
            static func configure() {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "Static.swift")
        let cls = artifact.types[0]
        #expect(cls.members.count == 3)
        #expect(cls.members[0].modifiers.contains(.static))
        #expect(cls.members[1].modifiers.contains(.class))
        #expect(cls.members[2].modifiers.contains(.static))
    }

    @Test func propertyWrappers() {
        let source = """
        @propertyWrapper
        struct Clamped<T: Comparable> {
            var wrappedValue: T
        }
        """
        let artifact = parser.parse(source: source, fileName: "Wrapper.swift")
        #expect(artifact.types.count == 1)
        let clamped = artifact.types[0]
        #expect(clamped.annotations.contains("@propertyWrapper"))
    }

    @Test func deinitializer() {
        let source = """
        class Resource {
            deinit {
                print("cleanup")
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Resource.swift")
        let resource = artifact.types[0]
        #expect(resource.members.count == 1)
        #expect(resource.members[0].kind == .deinitializer)
    }

    @Test func subscriptDeclaration() {
        let source = """
        struct Matrix {
            subscript(row: Int, col: Int) -> Double {
                get { 0.0 }
                set {}
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Matrix.swift")
        let matrix = artifact.types[0]
        #expect(matrix.members.count == 1)
        #expect(matrix.members[0].kind == .subscript)
        #expect(matrix.members[0].parameters.count == 2)
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
        #expect(artifact.relationships.count == 3)
    }

    @Test func variadicParameters() {
        let source = """
        func combine(values: Int...) -> Int {
            return values.reduce(0, +)
        }
        """
        let artifact = parser.parse(source: source, fileName: "Variadic.swift")
        #expect(artifact.freestandingFunctions.count == 1)
        let func_ = artifact.freestandingFunctions[0]
        #expect(func_.parameters.count == 1)
    }

    @Test func inoutParameters() {
        let source = """
        func swap(_ a: inout Int, _ b: inout Int) {
            let temp = a
            a = b
            b = temp
        }
        """
        let artifact = parser.parse(source: source, fileName: "Inout.swift")
        #expect(artifact.freestandingFunctions.count == 1)
    }

    @Test func lazyProperty() {
        let source = """
        class DataLoader {
            lazy var data: [String] = []
        }
        """
        let artifact = parser.parse(source: source, fileName: "Lazy.swift")
        let loader = artifact.types[0]
        #expect(loader.members[0].modifiers.contains(.lazy))
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

    @Test func convenienceInitializer() {
        let source = """
        class Person {
            init(name: String) {}
            convenience init() {
                self.init(name: "Unknown")
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Convenience.swift")
        let person = artifact.types[0]
        #expect(person.members.count == 2)
        #expect(person.members[1].modifiers.contains(.convenience))
    }

    @Test func optionalTypes() {
        let source = """
        struct Data {
            var value: String?
            var number: Int!
        }
        """
        let artifact = parser.parse(source: source, fileName: "Optional.swift")
        let data = artifact.types[0]
        #expect(data.members.count == 2)
        #expect(data.members[0].type?.name.contains("?") == true)
        #expect(data.members[1].type?.name.contains("!") == true)
    }

    @Test func arrayAndDictionaryTypes() {
        let source = """
        struct Container {
            var items: [String]
            var lookup: [String: Int]
            var matrix: [[Double]]
        }
        """
        let artifact = parser.parse(source: source, fileName: "Collections.swift")
        let container = artifact.types[0]
        #expect(container.members.count == 3)
    }
}
