import Foundation
import Testing
@testable import AcaiLibrary

/// Executable form of the parser producer-contract (#89): parses a small fixture with each bundled
/// `CodeParser`, enriches it exactly as the engine does, and asserts the `ParserConformanceChecker`
/// invariants hold. A deliberately-broken artifact (the negative test) proves the checker bites.
@Suite("Parser conformance")
struct ParserConformanceTests {

    struct Fixture: Sendable {
        let name: String
        let parser: any CodeParser
        let fileName: String
        let source: String
    }

    static let fixtures: [Fixture] = [
        Fixture(name: "Swift", parser: SwiftCodeParser(), fileName: "Zoo.swift", source: """
        class Animal { func speak() {} }
        class Dog: Animal {
            func bark() { self.speak() }
            struct Collar { var size: Int }
        }
        """),
        Fixture(name: "Java", parser: JavaCodeParser(), fileName: "Zoo.java", source: """
        package com.example;
        class Animal { void speak() {} }
        class Dog extends Animal {
            void bark() { this.speak(); }
            static class Collar { int size; }
        }
        """),
        Fixture(name: "Kotlin", parser: KotlinCodeParser(), fileName: "Zoo.kt", source: """
        package com.example
        open class Animal { fun speak() {} }
        class Dog : Animal() {
            fun bark() { this.speak() }
            class Collar { val size: Int = 0 }
        }
        """),
        Fixture(name: "TypeScript", parser: JSCodeParser(), fileName: "zoo.ts", source: """
        class Animal { speak(): void {} }
        class Dog extends Animal {
            bark(): void { this.speak() }
        }
        """),
        Fixture(name: "Python", parser: PythonCodeParser(), fileName: "zoo.py", source: """
        class Animal:
            def speak(self): pass
        class Dog(Animal):
            def bark(self): self.speak()
            class Collar: pass
        """),
        Fixture(name: "Dart", parser: DartCodeParser(), fileName: "zoo.dart", source: """
        class Animal { void speak() {} }
        class Dog extends Animal {
            void bark() { speak(); }
        }
        """),
        // C has no member functions or inheritance; what it *does* have — a typedef'd record, an
        // enum, a record-typed field and a free function over both — still has to produce resolvable
        // endpoints, which `struct Point` alone never exercised.
        Fixture(name: "C", parser: CCodeParser(), fileName: "zoo.c", source: """
        typedef enum Species { SpeciesDog, SpeciesCat } Species;

        typedef struct Collar { int size; } Collar;

        struct Animal {
            Collar collar;
            Species species;
        };

        int animal_collar_size(const struct Animal *animal) { return animal->collar.size; }
        """),
        // Constructors declared in the body, an `explicit` one, and the out-of-line definitions that
        // a real `.cpp` pairs them with — the shapes tree-sitter-cpp aliases to `declaration` and
        // `function_definition` rather than `field_declaration`.
        Fixture(name: "C++", parser: CppCodeParser(), fileName: "zoo.cpp", source: """
        namespace zoo {

        class Animal {
        public:
            Animal(int age);
            virtual void speak();
        protected:
            int age;
        };

        class Dog : public Animal {
        public:
            explicit Dog(int age);
            void bark();
            class Collar {
            public:
                Collar(int size);
                int size;
            };
        };

        void Dog::bark() { this->speak(); }

        }  // namespace zoo
        """)
    ]

    /// A fixture whose `method` reads the stored property `field` in expression position, used to prove
    /// every parser emits ``Member/fieldReads`` (issue #111). C is omitted — it has no member methods.
    struct ReadFixture: Sendable {
        let name: String
        let parser: any CodeParser
        let fileName: String
        let source: String
        let method: String
        let field: String
    }

    static let readFixtures: [ReadFixture] = [
        ReadFixture(name: "Swift", parser: SwiftCodeParser(), fileName: "Box.swift", source: """
        class Box {
            var value: Int = 0
            func get() -> Int { return value }
        }
        """, method: "get", field: "value"),
        ReadFixture(name: "Java", parser: JavaCodeParser(), fileName: "Box.java", source: """
        class Box {
            int value;
            int get() { return value; }
        }
        """, method: "get", field: "value"),
        ReadFixture(name: "Kotlin", parser: KotlinCodeParser(), fileName: "Box.kt", source: """
        class Box {
            var value: Int = 0
            fun get(): Int { return value }
        }
        """, method: "get", field: "value"),
        ReadFixture(name: "TypeScript", parser: JSCodeParser(), fileName: "box.ts", source: """
        class Box {
            value: number = 0
            get(): number { return this.value }
        }
        """, method: "get", field: "value"),
        ReadFixture(name: "Python", parser: PythonCodeParser(), fileName: "box.py", source: """
        class Box:
            def __init__(self):
                self.value = 0
            def get(self):
                return self.value
        """, method: "get", field: "value"),
        ReadFixture(name: "Dart", parser: DartCodeParser(), fileName: "box.dart", source: """
        class Box {
            int value = 0;
            int get() { return value; }
        }
        """, method: "get", field: "value"),
        ReadFixture(name: "C++", parser: CppCodeParser(), fileName: "box.cpp", source: """
        class Box {
        public:
            int value;
            int get() { return value; }
        };
        """, method: "get", field: "value")
    ]

    @Test(arguments: readFixtures)
    func parserCapturesOwnFieldReads(_ fixture: ReadFixture) {
        let parsed = fixture.parser.parse(source: fixture.source, fileName: fixture.fileName)
        let method = parsed.flattened().flatMap(\.members).first { $0.name == fixture.method }
        #expect(method != nil, "\(fixture.name): method '\(fixture.method)' not found")
        let readNames = method?.fieldReads.map(\.name) ?? []
        #expect(
            method?.fieldReads.contains { $0.name == fixture.field && $0.receiver == nil } == true,
            "\(fixture.name): expected a read of '\(fixture.field)', got \(readNames)")
    }

    @Test(arguments: fixtures)
    func parserSatisfiesProducerContract(_ fixture: Fixture) {
        let parsed = fixture.parser.parse(source: fixture.source, fileName: fixture.fileName)
        let enriched = parsed.enriched(configuration: fixture.parser.configuration)
        let violations = ParserConformanceChecker().violations(in: enriched)
        #expect(violations.isEmpty, "\(fixture.name): \(violations.map(\.description).joined(separator: "; "))")
        // Sanity: the fixture actually produced types, so the checks above weren't vacuous.
        #expect(!enriched.flattened().isEmpty, "\(fixture.name): parsed no types")
    }

    /// The checker must fail a deliberately non-conformant artifact — otherwise a green suite proves
    /// nothing. Violates invariant #1 (id != qualifiedName), #4 (qualified `TypeReference.name`) and
    /// #12 (nested id not prefixed).
    @Test func checkerCatchesContractViolations() {
        let bad = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Bad.swift"]),
            types: [
                TypeDeclaration(
                    id: "WrongId", name: "Outer", qualifiedName: "Outer", kind: .class,
                    accessLevel: .public,
                    members: [
                        Member(
                            name: "pet", kind: .property, accessLevel: .public,
                            type: TypeReference(name: "com.example.Animal"))
                    ],
                    nestedTypes: [
                        TypeDeclaration(
                            id: "Unrelated.Inner", name: "Inner", qualifiedName: "Unrelated.Inner",
                            kind: .class, accessLevel: .public)
                    ])
            ])
        let violations = ParserConformanceChecker().violations(in: bad)
        #expect(violations.contains { $0.invariant == 1 }, "should flag id != qualifiedName")
        #expect(violations.contains { $0.invariant == 4 }, "should flag a qualified TypeReference.name")
        #expect(violations.contains { $0.invariant == 12 }, "should flag unprefixed nested id")
    }

    /// Invariant #2's teeth: an endpoint left as a simple name that a declared type claims, and an
    /// empty endpoint. Both render a phantom node beside the real type instead of an edge to it.
    @Test func checkerCatchesUncanonicalisedEndpoints() {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Zoo.swift"]),
            types: [
                TypeDeclaration(
                    id: "zoo.Animal", name: "Animal", qualifiedName: "zoo.Animal", kind: .class,
                    accessLevel: .public),
                TypeDeclaration(
                    id: "zoo.Dog", name: "Dog", qualifiedName: "zoo.Dog", kind: .class,
                    accessLevel: .public,
                    inheritedTypes: [TypeReference(name: "Animal")])
            ],
            relationships: [
                Relationship(kind: .inheritance, source: "zoo.Dog", target: "Animal"),
                Relationship(kind: .dependency, source: "zoo.Dog", target: ""),
                // Legitimately external: nothing is declared under this name.
                Relationship(kind: .dependency, source: "zoo.Dog", target: "NSObject")
            ])
        let violations = ParserConformanceChecker().violations(in: artifact)
        #expect(
            violations.contains { $0.invariant == 2 && $0.detail.contains("target of a inheritance") },
            "should flag the unresolved 'Animal' relationship endpoint")
        #expect(
            violations.contains { $0.invariant == 2 && $0.detail.contains("supertype of 'zoo.Dog'") },
            "should flag the unresolved 'Animal' supertype")
        #expect(
            violations.contains { $0.invariant == 2 && $0.detail.contains("empty target") },
            "should flag the empty endpoint")
        #expect(
            !violations.contains { $0.detail.contains("NSObject") },
            "an external endpoint is legitimate and must not be flagged")
    }
}
