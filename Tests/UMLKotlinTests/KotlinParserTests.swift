import Testing
@testable import UMLKotlin
@testable import UMLCore

@Suite("Kotlin Parser Tests")
struct KotlinParserTests {
    let parser = KotlinCodeParser()

    // MARK: - Basic Declarations

    @Test func dataClass() {
        let source = """
        data class User(
            val name: String,
            val email: String,
            var age: Int = 0
        )
        """
        let artifact = parser.parse(source: source, fileName: "User.kt")
        #expect(artifact.types.count == 1)
        let user = artifact.types[0]
        #expect(user.name == "User")
        #expect(user.kind == .class)
        #expect(user.modifiers.contains(.data))
    }

    @Test func sealedClass() {
        let source = """
        sealed class Result {
            data class Success(val value: String) : Result()
            data class Error(val message: String) : Result()
        }
        """
        let artifact = parser.parse(source: source, fileName: "Result.kt")
        #expect(artifact.types.count == 1)
        let result = artifact.types[0]
        #expect(result.modifiers.contains(.sealed))
        #expect(result.nestedTypes.count == 2)
    }

    @Test func interfaceDeclaration() {
        let source = """
        interface Repository {
            fun findById(id: String): Entity?
            fun findAll(): List<Entity>
        }
        """
        let artifact = parser.parse(source: source, fileName: "Repository.kt")
        #expect(artifact.types.count == 1)
        let repo = artifact.types[0]
        #expect(repo.kind == .interface)
        #expect(repo.members.count == 2)
    }

    @Test func objectDeclaration() {
        let source = """
        object Singleton {
            val instance: String = "hello"
            fun doWork() {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "Singleton.kt")
        #expect(artifact.types.count == 1)
        let obj = artifact.types[0]
        #expect(obj.kind == .object)
        #expect(obj.name == "Singleton")
        #expect(obj.members.count == 2)
    }

    @Test func companionObject() {
        let source = """
        class Factory {
            companion object {
                fun create(): Factory = Factory()
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Factory.kt")
        let factory = artifact.types[0]
        #expect(factory.nestedTypes.count == 1)
        #expect(factory.nestedTypes[0].kind == .object)
    }

    @Test func enumClass() {
        let source = """
        enum class Direction {
            NORTH, SOUTH, EAST, WEST
        }
        """
        let artifact = parser.parse(source: source, fileName: "Direction.kt")
        #expect(artifact.types.count == 1)
        let dir = artifact.types[0]
        #expect(dir.kind == .enum)
        #expect(dir.enumCases.count == 4)
        #expect(dir.enumCases[0].name == "NORTH")
    }

    @Test func genericClass() {
        let source = """
        class Box<T : Comparable<T>>(val value: T) {
            fun compare(other: Box<T>): Int = 0
        }
        """
        let artifact = parser.parse(source: source, fileName: "Box.kt")
        let box = artifact.types[0]
        #expect(box.genericParameters.count == 1)
        #expect(box.genericParameters[0].name == "T")
    }

    @Test func nullableTypes() {
        let source = """
        class Config {
            val name: String? = null
            val count: Int = 0
        }
        """
        let artifact = parser.parse(source: source, fileName: "Config.kt")
        let config = artifact.types[0]
        let nameProperty = config.members.first { $0.name == "name" }
        #expect(nameProperty?.type?.isOptional == true)
    }

    @Test func abstractClass() {
        let source = """
        abstract class Shape {
            abstract fun area(): Double
            fun describe(): String = "Shape"
        }
        """
        let artifact = parser.parse(source: source, fileName: "Shape.kt")
        let shape = artifact.types[0]
        #expect(shape.modifiers.contains(.abstract))
    }

    @Test func packageNamespace() {
        let source = """
        package com.example.app

        class App {
            val version: String = "1.0"
        }
        """
        let artifact = parser.parse(source: source, fileName: "App.kt")
        let app = artifact.types[0]
        #expect(app.namespace == "com.example.app")
        #expect(app.id == "com.example.app.App")
    }

    @Test func functionDeclaration() {
        let source = """
        fun greet(name: String): String {
            return "Hello, $name"
        }
        """
        let artifact = parser.parse(source: source, fileName: "Greet.kt")
        #expect(artifact.freestandingFunctions.count == 1)
        #expect(artifact.freestandingFunctions[0].name == "greet")
    }

    // MARK: - Default Access Level (public)

    @Test func defaultAccessLevelIsPublic() {
        let source = """
        class Foo {
            val name: String = ""
            fun doSomething() {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "Foo.kt")
        let foo = artifact.types[0]
        #expect(foo.accessLevel == .public)
        let prop = foo.members.first { $0.name == "name" }
        #expect(prop?.accessLevel == .public)
        let method = foo.members.first { $0.name == "doSomething" }
        #expect(method?.accessLevel == .public)
    }

    @Test func explicitAccessLevels() {
        let source = """
        class Foo {
            private val secret: String = ""
            protected fun helper() {}
            internal val config: Int = 0
            public fun api() {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "Foo.kt")
        let foo = artifact.types[0]
        #expect(foo.members.first { $0.name == "secret" }?.accessLevel == .private)
        #expect(foo.members.first { $0.name == "helper" }?.accessLevel == .protected)
        #expect(foo.members.first { $0.name == "config" }?.accessLevel == .internal)
        #expect(foo.members.first { $0.name == "api" }?.accessLevel == .public)
    }

    @Test func internalClassAccessLevel() {
        let source = """
        internal class InternalService {
            fun process() {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "InternalService.kt")
        let svc = artifact.types[0]
        #expect(svc.accessLevel == .internal)
        // Members default to public even if the class is internal.
        let method = svc.members.first { $0.name == "process" }
        #expect(method?.accessLevel == .public)
    }

    // MARK: - Constructor Parameter Access Levels

    @Test func constructorParamAccessLevels() {
        let source = """
        class Person(
            private val name: String,
            val age: Int,
            protected var email: String
        )
        """
        let artifact = parser.parse(source: source, fileName: "Person.kt")
        let person = artifact.types[0]
        let nameProp = person.members.first { $0.name == "name" }
        #expect(nameProp?.accessLevel == .private)
        let ageProp = person.members.first { $0.name == "age" }
        #expect(ageProp?.accessLevel == .public)
        let emailProp = person.members.first { $0.name == "email" }
        #expect(emailProp?.accessLevel == .protected)
    }

    // MARK: - val → readonly Modifier

    @Test func valPropertyIsReadonly() {
        let source = """
        class Config {
            val name: String = "test"
            var count: Int = 0
        }
        """
        let artifact = parser.parse(source: source, fileName: "Config.kt")
        let config = artifact.types[0]
        let valProp = config.members.first { $0.name == "name" }
        #expect(valProp?.modifiers.contains(.readonly) == true)
        #expect(valProp?.modifiers.contains(.const) == false)
        let varProp = config.members.first { $0.name == "count" }
        #expect(varProp?.modifiers.contains(.readonly) == false)
    }

    @Test func constructorValIsReadonly() {
        let source = """
        data class Point(val x: Double, var y: Double)
        """
        let artifact = parser.parse(source: source, fileName: "Point.kt")
        let point = artifact.types[0]
        let xProp = point.members.first { $0.name == "x" }
        #expect(xProp?.modifiers.contains(.readonly) == true)
        let yProp = point.members.first { $0.name == "y" }
        #expect(yProp?.modifiers.contains(.readonly) == false)
    }

    @Test func constValHasBothModifiers() {
        let source = """
        class Constants {
            companion object {
                const val MAX_SIZE: Int = 100
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Constants.kt")
        let companion = artifact.types[0].nestedTypes[0]
        let maxSize = companion.members.first { $0.name == "MAX_SIZE" }
        // const val → both .const (from modifier) and .readonly (from val)
        #expect(maxSize?.modifiers.contains(.const) == true)
        #expect(maxSize?.modifiers.contains(.readonly) == true)
    }

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
