import Testing
@testable import UMLKotlin
@testable import UMLCore

@Suite("Kotlin Relationship & Feature Tests")
struct KotlinRelationshipTests {
    let parser = KotlinCodeParser()

    // MARK: - Relationships

    @Test func classInheritanceWithPackage() {
        let source = """
        package com.example.domain

        open class Animal {
            val name: String = ""
        }

        interface Describable {
            fun describe(): String
        }

        class Dog : Animal(), Describable {
            val breed: String = ""
            override fun describe(): String = "Dog: $name"
        }
        """
        let artifact = parser.parse(source: source, fileName: "Animals.kt")
        #expect(artifact.types.count == 3)

        let animal = artifact.types.first { $0.name == "Animal" }!
        let dog = artifact.types.first { $0.name == "Dog" }!
        #expect(animal.id == "com.example.domain.Animal")
        #expect(dog.id == "com.example.domain.Dog")

        // Relationship source and target must use qualified IDs matching type.id,
        // so that matching works without relying on downstream name resolution.
        let inheritance = artifact.relationships.first { $0.kind == .inheritance }
        #expect(inheritance?.source == "com.example.domain.Dog")
        #expect(inheritance?.target == "com.example.domain.Animal")

        let conformance = artifact.relationships.first { $0.kind == .conformance }
        #expect(conformance?.source == "com.example.domain.Dog")
        #expect(conformance?.target == "com.example.domain.Describable")
    }

    @Test func classInheritanceWithoutPackage() {
        let source = """
        class Dog : Animal(), Serializable {
            val breed: String = ""
        }
        """
        let artifact = parser.parse(source: source, fileName: "Dog.kt")
        #expect(artifact.relationships.count >= 2)
        let inheritance = artifact.relationships.first { $0.kind == .inheritance }
        #expect(inheritance?.target == "Animal")
        #expect(inheritance?.source == "Dog")
        let conformance = artifact.relationships.first { $0.kind == .conformance }
        #expect(conformance?.target == "Serializable")
    }

    @Test func interfaceInheritance() {
        let source = """
        interface MutableRepository : Repository, Closeable {
            fun save(entity: Entity)
        }
        """
        let artifact = parser.parse(source: source, fileName: "MutableRepository.kt")
        let iface = artifact.types[0]
        #expect(iface.kind == .interface)
        #expect(iface.inheritedTypes.count == 2)
        // Interface extends are modeled as conformance.
        let rels = artifact.relationships
        #expect(rels.count == 2)
        #expect(rels.allSatisfy { $0.kind == .conformance })
        #expect(rels.contains { $0.target == "Repository" })
        #expect(rels.contains { $0.target == "Closeable" })
    }

    @Test func objectExtendsClass() {
        let source = """
        object AppConfig : BaseConfig(), Serializable {
            val appName: String = "MyApp"
        }
        """
        let artifact = parser.parse(source: source, fileName: "AppConfig.kt")
        let obj = artifact.types[0]
        #expect(obj.kind == .object)
        let inheritance = artifact.relationships.first { $0.kind == .inheritance }
        #expect(inheritance?.target == "BaseConfig")
        let conformance = artifact.relationships.first { $0.kind == .conformance }
        #expect(conformance?.target == "Serializable")
    }

    @Test func enumImplementsInterface() {
        let source = """
        enum class Color : Displayable {
            RED, GREEN, BLUE;
            override fun display(): String = name
        }
        """
        let artifact = parser.parse(source: source, fileName: "Color.kt")
        let color = artifact.types[0]
        #expect(color.kind == .enum)
        #expect(color.enumCases.count == 3)
        let conformance = artifact.relationships.first { $0.kind == .conformance }
        #expect(conformance?.target == "Displayable")
    }

    @Test func nestedClassInheritanceWithPackage() {
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
        // Targets must use the qualified ID, not the short name.
        #expect(rels.allSatisfy { $0.target == "com.example.Result" })
    }

    // MARK: - Extension Functions

    @Test func extensionFunction() {
        let source = """
        fun String.isPalindrome(): Boolean {
            return this == this.reversed()
        }
        """
        let artifact = parser.parse(source: source, fileName: "StringExt.kt")
        #expect(artifact.freestandingFunctions.count == 1)
        #expect(artifact.freestandingFunctions[0].name == "isPalindrome")
        let extRel = artifact.relationships.first { $0.kind == .extension }
        #expect(extRel?.target == "String")
        #expect(extRel?.source == "isPalindrome")
    }

    @Test func genericExtensionFunction() {
        let source = """
        fun <T> List<T>.secondOrNull(): T? {
            return if (size >= 2) get(1) else null
        }
        """
        let artifact = parser.parse(source: source, fileName: "ListExt.kt")
        let extRel = artifact.relationships.first { $0.kind == .extension }
        #expect(extRel?.target == "List")
    }

    // MARK: - Type Alias

    @Test func typeAlias() {
        let source = """
        typealias StringMap = Map<String, String>
        """
        let artifact = parser.parse(source: source, fileName: "Aliases.kt")
        #expect(artifact.types.count == 1)
        let alias = artifact.types[0]
        #expect(alias.kind == .typeAlias)
        #expect(alias.name == "StringMap")
        #expect(alias.inheritedTypes.first?.name == "Map")
    }

    // MARK: - Secondary Constructor

    @Test func secondaryConstructor() {
        let source = """
        class Color(val hex: String) {
            constructor(r: Int, g: Int, b: Int) : this("#%02x%02x%02x".format(r, g, b))
        }
        """
        let artifact = parser.parse(source: source, fileName: "Color.kt")
        let color = artifact.types[0]
        let inits = color.members.filter { $0.kind == .initializer }
        #expect(inits.count == 2)
    }

    // MARK: - Computed Properties

    @Test func computedProperty() {
        let source = """
        class Circle(val radius: Double) {
            val area: Double
                get() = Math.PI * radius * radius
        }
        """
        let artifact = parser.parse(source: source, fileName: "Circle.kt")
        let circle = artifact.types[0]
        let area = circle.members.first { $0.name == "area" }
        #expect(area?.isComputed == true)
    }

    // MARK: - Annotation Class

    @Test func annotationClass() {
        let source = """
        annotation class JsonName(val name: String)
        """
        let artifact = parser.parse(source: source, fileName: "JsonName.kt")
        let annot = artifact.types[0]
        #expect(annot.kind == .annotation)
    }

    // MARK: - Inner Class

    @Test func innerClass() {
        let source = """
        class Outer {
            inner class Inner {
                fun foo() {}
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Outer.kt")
        let outer = artifact.types[0]
        #expect(outer.nestedTypes.count == 1)
        let inner = outer.nestedTypes[0]
        #expect(inner.modifiers.contains(.inner))
    }
}
