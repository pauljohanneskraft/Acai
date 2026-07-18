import Testing
@testable import AcaiJS
@testable import AcaiCore

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
        #expect(!artifact.types.isEmpty)
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
        // A non-exported class is module-local: the parser resolves it to `.internal` (never nil).
        let publicClass = artifact.types.first { $0.accessLevel == .public }
        let internalClass = artifact.types.first { $0.accessLevel == .internal }
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
