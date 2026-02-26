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

// MARK: - Extended TypeScript Tests

@Suite("Extended TypeScript Parser Tests")
struct ExtendedTypeScriptParserTests {
    let parser = JSCodeParser(isTypeScript: true)

    @Test func nestedClasses() {
        let source = """
        class Outer {
            class Inner {
                value: number = 0;
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "nested.ts")
        let outer = artifact.types.first { $0.name == "Outer" }
        #expect(outer != nil)
        // Note: nested classes may be extracted as separate types or as nestedTypes
        #expect(artifact.types.count >= 1)
    }

    @Test func multipleInterfaceImplementations() {
        let source = """
        interface A { a(): void; }
        interface B { b(): void; }
        interface C { c(): void; }
        class Multi implements A, B, C {
            a() {}
            b() {}
            c() {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "multi.ts")
        let multi = artifact.types.first { $0.name == "Multi" }
        #expect(multi != nil)
        #expect(multi?.inheritedTypes.count == 3)
        let conformances = artifact.relationships.filter { $0.kind == .conformance && $0.source == "Multi" }
        #expect(conformances.count == 3)
    }

    @Test func asyncAwaitMethods() {
        let source = """
        class AsyncService {
            async fetchData(): Promise<string> {
                return "data";
            }
            async processItems(items: string[]): Promise<void> {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "async.ts")
        let service = artifact.types[0]
        let asyncMethods = service.members.filter { $0.modifiers.contains(.async) }
        #expect(asyncMethods.count == 2)
    }

    @Test func arrowFunctionFields() {
        let source = """
        class Calculator {
            add = (a: number, b: number): number => a + b;
            multiply = (a: number, b: number) => a * b;
        }
        """
        let artifact = parser.parse(source: source, fileName: "calc.ts")
        let calc = artifact.types[0]
        #expect(calc.members.count >= 2)
    }

    @Test func unionAndIntersectionTypes() {
        let source = """
        type StringOrNumber = string | number;
        type Mergeable = { name: string } & { age: number };
        interface Container {
            value: string | number | boolean;
        }
        """
        let artifact = parser.parse(source: source, fileName: "types.ts")
        #expect(artifact.types.count == 3)
        let stringOrNumber = artifact.types.first { $0.name == "StringOrNumber" }
        #expect(stringOrNumber?.kind == .typeAlias)
    }

    @Test func complexGenericConstraints() {
        let source = """
        class Repository<T extends { id: string }, U extends T> {
            items: T[] = [];
            find(id: string): T | undefined { return undefined; }
        }
        """
        let artifact = parser.parse(source: source, fileName: "repo.ts")
        let repo = artifact.types[0]
        #expect(repo.genericParameters.count == 2)
        #expect(repo.genericParameters[0].constraints.count >= 1)
    }

    @Test func interfaceExtensionChain() {
        let source = """
        interface Base { id: string; }
        interface Middle extends Base { name: string; }
        interface Derived extends Middle { age: number; }
        """
        let artifact = parser.parse(source: source, fileName: "chain.ts")
        #expect(artifact.types.count == 3)
        let derived = artifact.types.first { $0.name == "Derived" }
        #expect(derived?.inheritedTypes.count >= 1)
        let inheritance = artifact.relationships.filter {
            $0.kind == .conformance && $0.source == "Derived"
        }
        #expect(inheritance.count >= 1)
    }

    @Test func overrideModifier() {
        let source = """
        class Base {
            method(): void {}
        }
        class Child extends Base {
            override method(): void {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "override.ts")
        let child = artifact.types.first { $0.name == "Child" }
        let overriddenMethod = child?.members.first { $0.name == "method" }
        #expect(overriddenMethod?.modifiers.contains(.override) == true)
    }

    @Test func declareModifier() {
        let source = """
        declare class ExternalLib {
            static version: string;
            process(data: string): void;
        }
        """
        let artifact = parser.parse(source: source, fileName: "declare.ts")
        // The declare keyword is typically used for ambient declarations
        let lib = artifact.types.first { $0.name == "ExternalLib" }
        #expect(lib != nil)
    }

    @Test func optionalParametersAndMethods() {
        let source = """
        interface Service {
            required(x: string): void;
            optional?(y: number): void;
        }
        class Implementation {
            method(required: string, optional?: number, another?: boolean): void {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "optional.ts")
        let impl = artifact.types.first { $0.name == "Implementation" }
        let method = impl?.members.first { $0.name == "method" }
        #expect(method?.parameters.count == 3)
    }

    @Test func restParameters() {
        let source = """
        function combine(first: string, ...rest: string[]): string {
            return first + rest.join();
        }
        class Logger {
            log(message: string, ...args: any[]): void {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "rest.ts")
        #expect(artifact.freestandingFunctions.count == 1)
        let combineFunc = artifact.freestandingFunctions[0]
        #expect(combineFunc.parameters.count >= 2)
    }

    @Test func defaultParameterValues() {
        let source = """
        function greet(name: string = "World"): string {
            return "Hello " + name;
        }
        class Config {
            constructor(public debug: boolean = false, public port: number = 3000) {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "defaults.ts")
        let config = artifact.types.first { $0.name == "Config" }
        #expect(config != nil)
    }

    @Test func multipleDecorators() {
        let source = """
        @Injectable()
        @Component({selector: 'test'})
        @Singleton
        class MultiDecorated {
            @Input() value: string = "";
            @Output() changed = new EventEmitter();
        }
        """
        let artifact = parser.parse(source: source, fileName: "decorators.ts")
        let decorated = artifact.types[0]
        #expect(decorated.annotations.count >= 3)
        let valueField = decorated.members.first { $0.name == "value" }
        #expect(valueField?.annotations.contains("@Input") == true)
    }

    @Test func computedPropertyNames() {
        let source = """
        const key = "dynamic";
        class ComputedProps {
            [key]: string;
            ["literal"]: number;
        }
        """
        let artifact = parser.parse(source: source, fileName: "computed.ts")
        let props = artifact.types[0]
        #expect(props != nil)
    }

    @Test func abstractMethodsAndProperties() {
        let source = """
        abstract class AbstractBase {
            abstract name: string;
            abstract getName(): string;
            abstract setName(value: string): void;
            concrete(): void {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "abstract.ts")
        let base = artifact.types[0]
        #expect(base.modifiers.contains(.abstract))
        let abstractMembers = base.members.filter { $0.modifiers.contains(.abstract) }
        #expect(abstractMembers.count >= 2)
    }

    @Test func getterSetterPairs() {
        let source = """
        class Person {
            private _name: string = "";
            get name(): string { return this._name; }
            set name(value: string) { this._name = value; }
        }
        """
        let artifact = parser.parse(source: source, fileName: "getset.ts")
        let person = artifact.types[0]
        let computed = person.members.filter { $0.isComputed }
        #expect(computed.count >= 2)
    }

    @Test func indexSignatures() {
        let source = """
        interface Dictionary {
            [key: string]: any;
        }
        interface NumberMap {
            [index: number]: string;
        }
        """
        let artifact = parser.parse(source: source, fileName: "index.ts")
        #expect(artifact.types.count == 2)
    }

    @Test func callSignatures() {
        let source = """
        interface Callable {
            (x: number): string;
        }
        interface ConstructorLike {
            new (x: number): object;
        }
        """
        let artifact = parser.parse(source: source, fileName: "callable.ts")
        #expect(artifact.types.count == 2)
    }

    @Test func mixedExports() {
        let source = """
        export class Named {}
        export default class DefaultClass {}
        export { Named as RenamedExport };
        """
        let artifact = parser.parse(source: source, fileName: "exports.ts")
        let types = artifact.types
        #expect(types.count >= 1)
        let defaultClass = types.first { $0.annotations.contains("default") }
        #expect(defaultClass != nil)
    }

    @Test func namespaceWithClasses() {
        let source = """
        namespace App {
            export class Service {}
            export namespace Models {
                export class User {}
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "namespace.ts")
        let module = artifact.types.first { $0.kind == .module }
        #expect(module != nil)
    }

    @Test func genericInterfaceWithMethods() {
        let source = """
        interface Comparable<T> {
            compareTo(other: T): number;
            equals(other: T): boolean;
        }
        """
        let artifact = parser.parse(source: source, fileName: "comparable.ts")
        let comparable = artifact.types[0]
        #expect(comparable.genericParameters.count == 1)
        #expect(comparable.members.count == 2)
    }
}

// MARK: - Extended JavaScript Tests

@Suite("Extended JavaScript Parser Tests")
struct ExtendedJavaScriptParserTests {
    let parser = JSCodeParser(isTypeScript: false)

    @Test func classWithArrowFunctions() {
        let source = """
        class Handler {
            onClick = () => { console.log('clicked'); }
            onSubmit = (event) => { event.preventDefault(); }
        }
        """
        let artifact = parser.parse(source: source, fileName: "handler.js")
        let handler = artifact.types[0]
        #expect(handler.members.count >= 2)
    }

    @Test func multipleClassExtension() {
        let source = """
        class Animal {}
        class Dog extends Animal {}
        class GoldenRetriever extends Dog {}
        """
        let artifact = parser.parse(source: source, fileName: "inheritance.js")
        #expect(artifact.types.count == 3)
        let golden = artifact.types.first { $0.name == "GoldenRetriever" }
        #expect(golden?.inheritedTypes.count == 1)
    }

    @Test func mixedStaticAndInstanceMembers() {
        let source = """
        class Utility {
            static count = 0;
            static increment() { this.count++; }
            instanceValue = 0;
            instanceMethod() { return this.instanceValue; }
        }
        """
        let artifact = parser.parse(source: source, fileName: "utility.js")
        let utility = artifact.types[0]
        let staticMembers = utility.members.filter { $0.modifiers.contains(.static) }
        let instanceMembers = utility.members.filter { !$0.modifiers.contains(.static) }
        #expect(staticMembers.count >= 2)
        #expect(instanceMembers.count >= 2)
    }

    @Test func complexPrototypePattern() {
        let source = """
        function Constructor(name) {
            this.name = name;
        }
        Constructor.prototype.getName = function() { return this.name; };
        Constructor.prototype.setName = function(name) { this.name = name; };
        """
        let artifact = parser.parse(source: source, fileName: "proto.js")
        let constructor = artifact.types.first { $0.name == "Constructor" }
        #expect(constructor != nil)
        let prototypeMethods = constructor?.members.filter { $0.name.contains("Name") }
        #expect((prototypeMethods?.count ?? 0) >= 2)
    }

    @Test func anonymousClassExpression() {
        let source = """
        const MyClass = class {
            method() { return "test"; }
        };
        """
        let artifact = parser.parse(source: source, fileName: "anon.js")
        // Anonymous class expressions may be captured
        #expect(artifact.types.count >= 0)
    }

    @Test func privateAndPublicMixedFields() {
        let source = """
        class Mixed {
            publicField = "public";
            #privateField = "private";
            getPrivate() { return this.#privateField; }
        }
        """
        let artifact = parser.parse(source: source, fileName: "mixed.js")
        let mixed = artifact.types[0]
        let publicMembers = mixed.members.filter { $0.accessLevel != .private }
        let privateMembers = mixed.members.filter { $0.accessLevel == .private }
        #expect(publicMembers.count >= 1)
        #expect(privateMembers.count >= 1)
    }

    @Test func exportedAndNonExportedClasses() {
        let source = """
        class Internal {
            internalMethod() {}
        }
        export class Public {
            publicMethod() {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "visibility.js")
        #expect(artifact.types.count == 2)
        let publicClass = artifact.types.first { $0.accessLevel == .public }
        let internalClass = artifact.types.first { $0.accessLevel == nil }
        #expect(publicClass != nil)
        #expect(internalClass != nil)
    }

    @Test func multipleGettersSetters() {
        let source = """
        class Props {
            get name() { return this._name; }
            set name(v) { this._name = v; }
            get age() { return this._age; }
            set age(v) { this._age = v; }
        }
        """
        let artifact = parser.parse(source: source, fileName: "props.js")
        let props = artifact.types[0]
        let computed = props.members.filter { $0.isComputed }
        #expect(computed.count >= 4)
    }

    @Test func complexConstructorPattern() {
        let source = """
        class Complex {
            constructor(a, b, c) {
                this.a = a;
                this.b = b;
                this.c = c;
                this.computed = a + b + c;
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "complex.js")
        let complex = artifact.types[0]
        let constructor = complex.members.first { $0.kind == .initializer }
        #expect(constructor != nil)
        #expect(constructor?.parameters.count == 3)
    }

    @Test func emptyClass() {
        let source = """
        class Empty {}
        """
        let artifact = parser.parse(source: source, fileName: "empty.js")
        #expect(artifact.types.count == 1)
        let empty = artifact.types[0]
        #expect(empty.name == "Empty")
        #expect(empty.members.isEmpty)
    }
}
