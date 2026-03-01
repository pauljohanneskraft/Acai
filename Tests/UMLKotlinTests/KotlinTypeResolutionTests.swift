import Testing
@testable import UMLCore
@testable import UMLKotlin

@Suite("Kotlin Type Resolution & Consistency Tests")
struct KotlinTypeResolutionTests {
    let parser = KotlinCodeParser()

    // MARK: - Qualified Type References

    @Test func qualifiedTypeReferenceInInheritance() {
        let source = """
        package com.example

        open class Animal(val name: String)

        class Dog(val breed: String) : Animal("Rex")
        """
        let artifact = parser.parse(source: source, fileName: "Animals.kt")
        let dog = artifact.types.first { $0.name == "Dog" }!
        #expect(dog.id == "com.example.Dog")

        let inheritance = artifact.relationships.first { $0.kind == .inheritance }
        #expect(inheritance?.source == "com.example.Dog")
        #expect(inheritance?.target == "com.example.Animal")
    }

    @Test func inheritedTypesAreResolved() {
        let source = """
        package com.example

        interface Identifiable {
            fun getId(): String
        }

        open class Animal(val name: String) : Identifiable {
            override fun getId(): String = name
        }

        class Dog(val breed: String) : Animal("Rex"), Identifiable
        """
        let artifact = parser.parse(source: source, fileName: "Animals.kt")
        let dog = artifact.types.first { $0.name == "Dog" }!
        // inheritedTypes names should use qualified IDs for same-file types.
        #expect(dog.inheritedTypes.contains { $0.name == "com.example.Animal" })
        #expect(dog.inheritedTypes.contains { $0.name == "com.example.Identifiable" })

        let animal = artifact.types.first { $0.name == "Animal" }!
        #expect(animal.inheritedTypes.contains { $0.name == "com.example.Identifiable" })
    }

    // MARK: - Nested Type IDs

    @Test func nestedTypeHasCorrectQualifiedId() {
        let source = """
        package com.example

        sealed class Result {
            data class Success(val value: String) : Result()
            data class Failure(val error: Throwable) : Result()
        }
        """
        let artifact = parser.parse(source: source, fileName: "Result.kt")
        let result = artifact.types.first { $0.name == "Result" }!
        let success = result.nestedTypes.first { $0.name == "Success" }!
        let failure = result.nestedTypes.first { $0.name == "Failure" }!

        // Nested types must include the parent in their qualified ID.
        #expect(success.id == "com.example.Result.Success")
        #expect(success.qualifiedName == "com.example.Result.Success")
        #expect(failure.id == "com.example.Result.Failure")
        #expect(failure.qualifiedName == "com.example.Result.Failure")
    }

    @Test func nestedTypeInheritanceSourceUsesQualifiedId() {
        let source = """
        package com.example

        sealed class Result {
            data class Success(val value: String) : Result()
            data class Failure(val error: Throwable) : Result()
        }
        """
        let artifact = parser.parse(source: source, fileName: "Result.kt")
        let rels = artifact.relationships.filter { $0.kind == .inheritance }
        #expect(rels.count == 2)
        // Sources must be the fully-qualified nested type IDs.
        #expect(rels.contains { $0.source == "com.example.Result.Success" })
        #expect(rels.contains { $0.source == "com.example.Result.Failure" })
        // Targets must point to the parent's qualified ID.
        #expect(rels.allSatisfy { $0.target == "com.example.Result" })
    }

    @Test func deeplyNestedTypeIds() {
        let source = """
        package com.example

        class Outer {
            class Middle {
                class Inner {
                    val name: String = ""
                }
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Outer.kt")
        let outer = artifact.types.first { $0.name == "Outer" }!
        let middle = outer.nestedTypes.first { $0.name == "Middle" }!
        let inner = middle.nestedTypes.first { $0.name == "Inner" }!

        #expect(outer.id == "com.example.Outer")
        #expect(middle.id == "com.example.Outer.Middle")
        #expect(inner.id == "com.example.Outer.Middle.Inner")
    }

    // MARK: - Nested Class Type References Preserve Nesting

    @Test func nestedClassTypeReferencePreservesNesting() {
        let source = """
        package com.example

        class Outer {
            class Inner(val name: String)

            val child: Inner = Inner("test")
        }
        """
        let artifact = parser.parse(source: source, fileName: "Outer.kt")
        let outer = artifact.types.first { $0.name == "Outer" }!
        let childProp = outer.members.first { $0.name == "child" }
        // The type reference for "Inner" should be present.
        #expect(childProp?.type?.name == "Inner")
    }

    // MARK: - Relationship Consistency with Package

    @Test func allRelationshipsUseQualifiedIdsWhenInSameFile() {
        let source = """
        package com.example.domain

        interface Identifiable {
            fun getId(): String
        }

        interface Named {
            val name: String
        }

        open class BaseEntity : Identifiable {
            override fun getId(): String = ""
        }

        class User : BaseEntity(), Named {
            override val name: String = ""
        }
        """
        let artifact = parser.parse(source: source, fileName: "Domain.kt")

        // All relationships in the same file should have qualified source and target.
        for rel in artifact.relationships {
            #expect(
                rel.source.contains("com.example.domain"),
                "source '\(rel.source)' should be qualified"
            )
            // Targets should also be qualified for same-file types.
            #expect(
                rel.target.contains("com.example.domain"),
                "target '\(rel.target)' should be qualified"
            )
        }
    }

    @Test func crossFileRelationshipTargetsUseSimpleNames() {
        // When parsing a single file, references to types NOT in the same file
        // remain as simple names (resolution happens later in the enricher).
        let source = """
        package com.example.app

        class Dog(val breed: String) : Animal("Rex"), Serializable
        """
        let artifact = parser.parse(source: source, fileName: "Dog.kt")
        let inheritance = artifact.relationships.first { $0.kind == .inheritance }
        #expect(inheritance?.source == "com.example.app.Dog")
        // "Animal" is not in this file, so it stays as is.
        #expect(inheritance?.target == "Animal")
    }

    // MARK: - Object with Supertype

    @Test func objectWithSuperclassInPackage() {
        let source = """
        package com.example

        open class Config

        object AppConfig : Config() {
            val appName: String = "MyApp"
        }
        """
        let artifact = parser.parse(source: source, fileName: "Config.kt")
        let inheritance = artifact.relationships.first { $0.kind == .inheritance }
        #expect(inheritance?.source == "com.example.AppConfig")
        #expect(inheritance?.target == "com.example.Config")
    }

    // MARK: - Enum with Interface in Package

    @Test func enumWithInterfaceInPackage() {
        let source = """
        package com.example

        interface Displayable {
            fun display(): String
        }

        enum class Color : Displayable {
            RED, GREEN, BLUE;
            override fun display(): String = name
        }
        """
        let artifact = parser.parse(source: source, fileName: "Color.kt")
        let conformance = artifact.relationships.first { $0.kind == .conformance }
        #expect(conformance?.source == "com.example.Color")
        #expect(conformance?.target == "com.example.Displayable")
    }

    // MARK: - Multi-File Simulation

    @Test func multiFileInheritanceProducesResolvableRelationship() {
        // File 1: defines Animal
        let source1 = """
        package com.example

        open class Animal(val name: String)
        """
        // File 2: defines Dog extending Animal
        let source2 = """
        package com.example

        class Dog(val breed: String) : Animal("Rex")
        """
        let artifact1 = parser.parse(source: source1, fileName: "Animal.kt")
        let artifact2 = parser.parse(source: source2, fileName: "Dog.kt")
        let merged = artifact1.merging(with: artifact2)

        // Relationship must exist with qualified source and simple target.
        let inheritance = merged.relationships.first { $0.kind == .inheritance }
        #expect(inheritance?.source == "com.example.Dog")
        // Target is just "Animal" because it's not defined in Dog.kt.
        #expect(inheritance?.target == "Animal")

        // Both types must be in the merged artifact.
        #expect(merged.types.contains { $0.id == "com.example.Animal" })
        #expect(merged.types.contains { $0.id == "com.example.Dog" })
    }

    @Test func multiFileInterfaceConformanceRelationship() {
        let source1 = """
        package com.example

        interface Identifiable {
            fun getId(): String
        }
        """
        let source2 = """
        package com.example

        class User(val name: String) : Identifiable {
            override fun getId(): String = name
        }
        """
        let artifact1 = parser.parse(source: source1, fileName: "Identifiable.kt")
        let artifact2 = parser.parse(source: source2, fileName: "User.kt")
        let merged = artifact1.merging(with: artifact2)

        let conformance = merged.relationships.first { $0.kind == .conformance }
        #expect(conformance?.source == "com.example.User")
        #expect(conformance?.target == "Identifiable")

        #expect(merged.types.contains { $0.id == "com.example.Identifiable" })
        #expect(merged.types.contains { $0.id == "com.example.User" })
    }
}
