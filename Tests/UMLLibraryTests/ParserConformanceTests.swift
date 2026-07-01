import Foundation
import Testing
@testable import UMLLibrary

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
        Fixture(name: "C", parser: CCodeParser(), fileName: "zoo.c", source: """
        struct Point { int x; int y; };
        """),
        Fixture(name: "C++", parser: CppCodeParser(), fileName: "zoo.cpp", source: """
        class Animal { public: void speak(); };
        class Dog : public Animal {
        public:
            void bark();
            class Collar { public: int size; };
        };
        """)
    ]

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
    /// nothing. Violates invariant #1 (id != qualifiedName) and #12 (nested id not prefixed).
    @Test func checkerCatchesContractViolations() {
        let bad = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Bad.swift"]),
            types: [
                TypeDeclaration(
                    id: "WrongId", name: "Outer", qualifiedName: "Outer", kind: .class,
                    accessLevel: .public,
                    nestedTypes: [
                        TypeDeclaration(
                            id: "Unrelated.Inner", name: "Inner", qualifiedName: "Unrelated.Inner",
                            kind: .class, accessLevel: .public)
                    ])
            ])
        let violations = ParserConformanceChecker().violations(in: bad)
        #expect(violations.contains { $0.invariant == 1 }, "should flag id != qualifiedName")
        #expect(violations.contains { $0.invariant == 12 }, "should flag unprefixed nested id")
    }
}
