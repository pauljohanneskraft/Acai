import Testing
@testable import UMLJVM
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

}
