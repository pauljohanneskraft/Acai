import Testing
@testable import UMLJS
@testable import UMLCore

@Suite("TypeScript Parser Tests")
struct TypeScriptParserTests {
    let parser = JSCodeParser(isTypeScript: true)

    @Test func classDeclaration() {
        let source = """
        class Animal {
            name: string;
            constructor(name: string) { this.name = name; }
            speak(): string { return this.name; }
        }
        """
        let artifact = parser.parse(source: source, fileName: "animal.ts")
        #expect(artifact.types.count == 1)
        let animal = artifact.types[0]
        #expect(animal.name == "Animal")
        #expect(animal.kind == .class)
    }

    @Test func interfaceDeclaration() {
        let source = """
        interface Repository<T> {
            findById(id: string): Promise<T>;
            findAll(): Promise<T[]>;
        }
        """
        let artifact = parser.parse(source: source, fileName: "repo.ts")
        #expect(artifact.types.count == 1)
        let repo = artifact.types[0]
        #expect(repo.kind == .interface)
        #expect(repo.genericParameters.count == 1)
        #expect(repo.members.count == 2)
    }

    @Test func typeAlias() {
        let source = """
        type Result<T> = Success<T> | Failure;
        """
        let artifact = parser.parse(source: source, fileName: "types.ts")
        #expect(artifact.types.count == 1)
        #expect(artifact.types[0].kind == .typeAlias)
        #expect(artifact.types[0].name == "Result")
    }

    @Test func enumDeclaration() {
        let source = """
        enum Direction {
            Up = "UP",
            Down = "DOWN",
            Left = "LEFT",
            Right = "RIGHT"
        }
        """
        let artifact = parser.parse(source: source, fileName: "dir.ts")
        #expect(artifact.types.count == 1)
        let dir = artifact.types[0]
        #expect(dir.kind == .enum)
        #expect(dir.enumCases.count == 4)
        #expect(dir.enumCases[0].rawValue == "\"UP\"")
    }

    @Test func abstractClass() {
        let source = """
        abstract class Shape {
            abstract area(): number;
            perimeter(): number { return 0; }
        }
        """
        let artifact = parser.parse(source: source, fileName: "shape.ts")
        let shape = artifact.types[0]
        #expect(shape.modifiers.contains(.abstract))
    }

    @Test func decorator() {
        let source = """
        @Component({selector: 'app'})
        export class AppComponent {
            title: string = "Hello";
        }
        """
        let artifact = parser.parse(source: source, fileName: "app.ts")
        let comp = artifact.types[0]
        #expect(comp.annotations.contains("@Component"))
        #expect(comp.accessLevel == .public)
    }

    @Test func extendsImplements() {
        let source = """
        class Dog extends Animal implements Serializable, Printable {
            breed: string = "";
        }
        """
        let artifact = parser.parse(source: source, fileName: "dog.ts")
        #expect(artifact.relationships.count >= 3)
        let inheritance = artifact.relationships.first { $0.kind == .inheritance }
        #expect(inheritance?.target == "Animal")
        let conformances = artifact.relationships.filter { $0.kind == .conformance }
        #expect(conformances.count == 2)
    }

    @Test func genericClass() {
        let source = """
        class Container<T extends Comparable> {
            private value: T;
            constructor(value: T) { this.value = value; }
        }
        """
        let artifact = parser.parse(source: source, fileName: "container.ts")
        let container = artifact.types[0]
        #expect(container.genericParameters.count == 1)
        #expect(container.genericParameters[0].constraints.count == 1)
    }

    @Test func readonlyOptional() {
        let source = """
        interface Config {
            readonly name: string;
            debug?: boolean;
            version: string;
        }
        """
        let artifact = parser.parse(source: source, fileName: "config.ts")
        let config = artifact.types[0]
        let nameP = config.members.first { $0.name == "name" }
        #expect(nameP?.modifiers.contains(.readonly) == true)
    }

    @Test func parameterProperties() {
        let source = """
        class Foo {
            constructor(public name: string, private age: number) {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "foo.ts")
        let foo = artifact.types[0]
        let properties = foo.members.filter { $0.kind == .property }
        #expect(properties.count == 2)
        // #expect(properties[0].name == "name")
        // #expect(properties[0].accessLevel == .public)
        // #expect(properties[1].name == "age")
        // #expect(properties[1].accessLevel == .private)
    }

    @Test func namespace() {
        let source = """
        namespace MyLib {
            export class Helper {
                run(): void {}
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "lib.ts")
        #expect(artifact.types.count >= 1)
        let moduleType = artifact.types.first { $0.kind == .module }
        #expect(moduleType?.name == "MyLib")
    }

    @Test func exportDefault() {
        let source = """
        export default class Main {
            start(): void {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "main.ts")
        let main = artifact.types[0]
        #expect(main.accessLevel == .public)
        #expect(main.annotations.contains("default"))
    }

    @Test func freestandingFunction() {
        let source = """
        export function helper(x: number, y: number): number { return x + y; }
        """
        let artifact = parser.parse(source: source, fileName: "helpers.ts")
        #expect(artifact.freestandingFunctions.count == 1)
        #expect(artifact.freestandingFunctions[0].name == "helper")
    }
}

@Suite("JavaScript Parser Tests")
struct JavaScriptParserTests {
    let parser = JSCodeParser(isTypeScript: false)

    @Test func simpleClass() {
        let source = """
        class Animal {
            constructor(name) { this.name = name; }
            speak() { return this.name; }
        }
        """
        let artifact = parser.parse(source: source, fileName: "animal.js")
        #expect(artifact.types.count == 1)
        let animal = artifact.types[0]
        #expect(animal.name == "Animal")
        #expect(artifact.metadata.sourceLanguage == .javaScript)
    }

    @Test func classExtends() {
        let source = """
        class Dog extends Animal {
            constructor(name, breed) { super(name); this.breed = breed; }
            bark() {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "dog.js")
        let dog = artifact.types[0]
        #expect(dog.inheritedTypes.count == 1)
        #expect(artifact.relationships.first?.kind == .inheritance)
    }

    @Test func staticMembers() {
        let source = """
        class Counter {
            static count = 0;
            static increment() { Counter.count++; }
        }
        """
        let artifact = parser.parse(source: source, fileName: "counter.js")
        let counter = artifact.types[0]
        #expect(counter.members.contains { $0.modifiers.contains(.static) })
    }

    @Test func getterSetter() {
        let source = """
        class Person {
            get fullName() { return this.first + ' ' + this.last; }
            set fullName(value) { }
        }
        """
        let artifact = parser.parse(source: source, fileName: "person.js")
        let person = artifact.types[0]
        let getterSetter = person.members.filter { $0.isComputed }
        #expect(getterSetter.count >= 1)
    }

    @Test func privateFields() {
        let source = """
        class Foo {
            #count = 0;
            #increment() { this.#count++; }
            getCount() { return this.#count; }
        }
        """
        let artifact = parser.parse(source: source, fileName: "foo.js")
        let foo = artifact.types[0]
        let privateMembers = foo.members.filter { $0.accessLevel == .private }
        #expect(privateMembers.count == 2)
    }

    @Test func exportClass() {
        let source = """
        export class Service {
            fetch() {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "service.js")
        #expect(artifact.types[0].accessLevel == .public)
    }

    @Test func prototypeMethod() {
        let source = """
        function Foo() {}
        Foo.prototype.bar = function() {};
        """
        let artifact = parser.parse(source: source, fileName: "foo.js")
        let foo = artifact.types.first { $0.name == "Foo" }
        #expect(foo != nil)
        #expect(foo?.members.contains { $0.name == "bar" } == true)
    }

    @Test func freestandingFunction() {
        let source = """
        function helper(x, y) { return x + y; }
        """
        let artifact = parser.parse(source: source, fileName: "helpers.js")
        #expect(artifact.freestandingFunctions.count == 1)
        #expect(artifact.freestandingFunctions[0].name == "helper")
    }
}
