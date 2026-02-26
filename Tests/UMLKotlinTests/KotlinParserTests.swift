import Testing
@testable import UMLKotlin
@testable import UMLCore

@Suite("Kotlin Parser Tests")
struct KotlinParserTests {
    let parser = KotlinCodeParser()

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

    @Test func classInheritance() {
        let source = """
        class Dog : Animal(), Serializable {
            val breed: String = ""
        }
        """
        let artifact = parser.parse(source: source, fileName: "Dog.kt")
        #expect(artifact.relationships.count >= 2)
        let inheritance = artifact.relationships.first { $0.kind == .inheritance }
        #expect(inheritance?.target == "Animal")
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

    // MARK: - Property Modifiers Tests

    @Test func valProperty() {
        let source = """
        class Config {
            val readOnly: String = "immutable"
        }
        """
        let artifact = parser.parse(source: source, fileName: "Config.kt")
        let config = artifact.types[0]
        let prop = config.members.first { $0.name == "readOnly" }
        #expect(prop?.modifiers.contains(.const) == true)
    }

    @Test func varProperty() {
        let source = """
        class Config {
            var mutable: String = "changeable"
        }
        """
        let artifact = parser.parse(source: source, fileName: "Config.kt")
        let config = artifact.types[0]
        let prop = config.members.first { $0.name == "mutable" }
        #expect(prop?.modifiers.contains(.const) == false)
    }

    @Test func lateinitProperty() {
        let source = """
        class Service {
            private lateinit var repository: Repository
        }
        """
        let artifact = parser.parse(source: source, fileName: "Service.kt")
        let service = artifact.types[0]
        let prop = service.members.first { $0.name == "repository" }
        #expect(prop?.modifiers.contains(.lazy) == true)
        #expect(prop?.accessLevel == .private)
    }

    @Test func constProperty() {
        let source = """
        class Constants {
            companion object {
                const val MAX_SIZE: Int = 100
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Constants.kt")
        let constants = artifact.types[0]
        let companion = constants.nestedTypes.first
        #expect(companion != nil)
        let prop = companion?.members.first { $0.name == "MAX_SIZE" }
        #expect(prop?.modifiers.contains(.const) == true)
    }

    // MARK: - Function Modifier Tests

    @Test func suspendFunction() {
        let source = """
        class AsyncService {
            suspend fun fetchData(): String {
                return "data"
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "AsyncService.kt")
        let service = artifact.types[0]
        let method = service.members.first { $0.name == "fetchData" }
        #expect(method?.modifiers.contains(.suspend) == true)
    }

    @Test func inlineFunction() {
        let source = """
        class Utils {
            inline fun <reified T> process(): T? = null
        }
        """
        let artifact = parser.parse(source: source, fileName: "Utils.kt")
        let utils = artifact.types[0]
        let method = utils.members.first { $0.name == "process" }
        #expect(method?.modifiers.contains(.inline) == true)
    }

    @Test func overrideFunction() {
        let source = """
        class Dog : Animal() {
            override fun makeSound(): String = "Woof"
        }
        """
        let artifact = parser.parse(source: source, fileName: "Dog.kt")
        let dog = artifact.types[0]
        let method = dog.members.first { $0.name == "makeSound" }
        #expect(method?.modifiers.contains(.override) == true)
    }

    // MARK: - Type Alias Tests

    @Test func typeAlias() {
        let source = """
        typealias UserMap = Map<String, User>
        """
        let artifact = parser.parse(source: source, fileName: "TypeAlias.kt")
        #expect(artifact.types.count == 1)
        let alias = artifact.types[0]
        #expect(alias.kind == .typeAlias)
        #expect(alias.name == "UserMap")
    }

    @Test func genericTypeAlias() {
        let source = """
        typealias StringList<T> = List<T>
        """
        let artifact = parser.parse(source: source, fileName: "GenericAlias.kt")
        let alias = artifact.types[0]
        #expect(alias.kind == .typeAlias)
        #expect(alias.genericParameters.count == 1)
    }

    @Test func nullableTypeAlias() {
        let source = """
        typealias NullableString = String?
        """
        let artifact = parser.parse(source: source, fileName: "NullableAlias.kt")
        let alias = artifact.types[0]
        #expect(alias.kind == .typeAlias)
        #expect(alias.inheritedTypes.first?.isOptional == true)
    }

    // MARK: - Secondary Constructor Tests

    @Test func secondaryConstructor() {
        let source = """
        class Person(val name: String) {
            var age: Int = 0

            constructor(name: String, age: Int) : this(name) {
                this.age = age
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Person.kt")
        let person = artifact.types[0]
        let constructors = person.members.filter { $0.kind == .initializer }
        #expect(constructors.count >= 2)
    }

    // MARK: - Extension Function Tests

    @Test func extensionFunction() {
        let source = """
        fun String.toTitleCase(): String {
            return this.capitalize()
        }
        """
        let artifact = parser.parse(source: source, fileName: "Extensions.kt")
        #expect(artifact.freestandingFunctions.count == 1)
        let extensionRel = artifact.relationships.first { $0.kind == .extension }
        #expect(extensionRel != nil)
        #expect(extensionRel?.target == "String")
    }

    @Test func classExtensionFunction() {
        let source = """
        class Utils {
            fun List<Int>.sum(): Int = 0
        }
        """
        let artifact = parser.parse(source: source, fileName: "ClassExtensions.kt")
        let utils = artifact.types[0]
        #expect(utils.members.count >= 1)
    }

    // MARK: - Annotation Tests

    @Test func classAnnotation() {
        let source = """
        @Entity
        @Table(name = "users")
        data class User(val id: Long)
        """
        let artifact = parser.parse(source: source, fileName: "User.kt")
        let user = artifact.types[0]
        #expect(user.annotations.count >= 2)
        #expect(user.annotations.contains("@Entity"))
    }

    @Test func methodAnnotation() {
        let source = """
        class Service {
            @Deprecated("Use newMethod instead")
            fun oldMethod() {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "Service.kt")
        let service = artifact.types[0]
        let method = service.members.first { $0.name == "oldMethod" }
        #expect(method?.annotations.isEmpty == false)
    }

    @Test func propertyAnnotation() {
        let source = """
        class Model {
            @JsonProperty("user_name")
            val userName: String = ""
        }
        """
        let artifact = parser.parse(source: source, fileName: "Model.kt")
        let model = artifact.types[0]
        let prop = model.members.first { $0.name == "userName" }
        #expect(prop?.annotations.isEmpty == false)
    }

    @Test func annotationClass() {
        let source = """
        annotation class MyAnnotation(val value: String)
        """
        let artifact = parser.parse(source: source, fileName: "Annotation.kt")
        #expect(artifact.types.count == 1)
        let annot = artifact.types[0]
        #expect(annot.kind == .annotation)
    }

    // MARK: - Computed Property Tests

    @Test func computedProperty() {
        let source = """
        class Rectangle(val width: Int, val height: Int) {
            val area: Int
                get() = width * height
        }
        """
        let artifact = parser.parse(source: source, fileName: "Rectangle.kt")
        let rect = artifact.types[0]
        let area = rect.members.first { $0.name == "area" }
        #expect(area?.isComputed == true)
    }

    @Test func propertyWithGetterAndSetter() {
        let source = """
        class Temperature {
            var celsius: Double = 0.0
                get() = field
                set(value) { field = value }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Temperature.kt")
        let temp = artifact.types[0]
        let prop = temp.members.first { $0.name == "celsius" }
        #expect(prop?.isComputed == true)
    }

    // MARK: - Vararg Parameter Tests

    @Test func varargParameter() {
        let source = """
        class Printer {
            fun print(vararg messages: String) {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "Printer.kt")
        let printer = artifact.types[0]
        let method = printer.members.first { $0.name == "print" }
        #expect(method?.parameters.first?.isVariadic == true)
    }

    @Test func functionWithVarargAndRegularParams() {
        let source = """
        fun format(prefix: String, vararg values: Any): String = ""
        """
        let artifact = parser.parse(source: source, fileName: "Format.kt")
        let func = artifact.freestandingFunctions[0]
        #expect(func.parameters.count == 2)
        #expect(func.parameters[0].isVariadic == false)
        #expect(func.parameters[1].isVariadic == true)
    }

    // MARK: - Function Type Tests

    @Test func functionTypeParameter() {
        let source = """
        class Handler {
            fun execute(callback: (String) -> Unit) {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "Handler.kt")
        let handler = artifact.types[0]
        let method = handler.members.first { $0.name == "execute" }
        #expect(method?.parameters.count == 1)
    }

    @Test func functionTypeProperty() {
        let source = """
        class EventManager {
            var onEvent: ((Event) -> Unit)? = null
        }
        """
        let artifact = parser.parse(source: source, fileName: "EventManager.kt")
        let manager = artifact.types[0]
        let prop = manager.members.first { $0.name == "onEvent" }
        #expect(prop?.type?.isOptional == true)
    }

    // MARK: - Inner Class Tests

    @Test func innerClass() {
        let source = """
        class Outer {
            inner class Inner {
                fun access() {}
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Outer.kt")
        let outer = artifact.types[0]
        #expect(outer.nestedTypes.count == 1)
        let inner = outer.nestedTypes[0]
        #expect(inner.modifiers.contains(.inner) == true)
    }

    // MARK: - Enum with Values Tests

    @Test func enumWithValues() {
        let source = """
        enum class Color(val rgb: Int) {
            RED(0xFF0000),
            GREEN(0x00FF00),
            BLUE(0x0000FF)
        }
        """
        let artifact = parser.parse(source: source, fileName: "Color.kt")
        let color = artifact.types[0]
        #expect(color.kind == .enum)
        #expect(color.enumCases.count == 3)
        #expect(color.enumCases[0].rawValue != nil)
    }

    @Test func enumWithMethods() {
        let source = """
        enum class Operation {
            ADD,
            SUBTRACT;

            fun execute(a: Int, b: Int): Int = 0
        }
        """
        let artifact = parser.parse(source: source, fileName: "Operation.kt")
        let operation = artifact.types[0]
        #expect(operation.kind == .enum)
        #expect(operation.enumCases.count == 2)
        #expect(operation.members.count >= 1)
    }

    // MARK: - Call Site Tests

    @Test func methodCallSites() {
        let source = """
        class Service {
            val repository: Repository = Repository()

            fun loadData() {
                repository.findAll()
                repository.save()
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Service.kt")
        let service = artifact.types[0]
        let method = service.members.first { $0.name == "loadData" }
        #expect(method?.callSites.isEmpty == false)
    }

    @Test func thisCallSites() {
        let source = """
        class Manager {
            val handler: Handler = Handler()

            fun process() {
                this.handler.handle()
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Manager.kt")
        let manager = artifact.types[0]
        let method = manager.members.first { $0.name == "process" }
        #expect(method?.callSites.isEmpty == false)
    }

    // MARK: - Generic Constraint Tests

    @Test func genericConstraint() {
        let source = """
        class Container<T : Comparable<T>>(val value: T) {
            fun compare(other: T): Int = 0
        }
        """
        let artifact = parser.parse(source: source, fileName: "Container.kt")
        let container = artifact.types[0]
        #expect(container.genericParameters.count == 1)
        let generic = container.genericParameters[0]
        #expect(generic.constraints.isEmpty == false)
    }

    @Test func multipleGenericConstraints() {
        let source = """
        interface Processor<T> where T : Serializable, T : Comparable<T> {
            fun process(item: T)
        }
        """
        let artifact = parser.parse(source: source, fileName: "Processor.kt")
        let processor = artifact.types[0]
        #expect(processor.genericParameters.count == 1)
    }

    // MARK: - Visibility Modifier Tests

    @Test func publicVisibility() {
        let source = """
        public class PublicClass {
            public fun publicMethod() {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "Public.kt")
        let cls = artifact.types[0]
        #expect(cls.accessLevel == .public)
        let method = cls.members.first { $0.name == "publicMethod" }
        #expect(method?.accessLevel == .public)
    }

    @Test func privateVisibility() {
        let source = """
        class Container {
            private val secret: String = ""
            private fun privateMethod() {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "Private.kt")
        let container = artifact.types[0]
        let prop = container.members.first { $0.name == "secret" }
        #expect(prop?.accessLevel == .private)
        let method = container.members.first { $0.name == "privateMethod" }
        #expect(method?.accessLevel == .private)
    }

    @Test func protectedVisibility() {
        let source = """
        open class Base {
            protected val value: Int = 0
            protected fun protectedMethod() {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "Protected.kt")
        let base = artifact.types[0]
        let prop = base.members.first { $0.name == "value" }
        #expect(prop?.accessLevel == .protected)
    }

    @Test func internalVisibility() {
        let source = """
        internal class InternalClass {
            internal fun internalMethod() {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "Internal.kt")
        let cls = artifact.types[0]
        #expect(cls.accessLevel == .internal)
    }

    // MARK: - Open and Final Modifier Tests

    @Test func openClass() {
        let source = """
        open class Base {
            open fun overridable() {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "Open.kt")
        let base = artifact.types[0]
        #expect(base.modifiers.contains(.open) == true)
        let method = base.members.first { $0.name == "overridable" }
        #expect(method?.modifiers.contains(.open) == true)
    }

    @Test func finalModifier() {
        let source = """
        class Container {
            final fun cannotOverride() {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "Final.kt")
        let container = artifact.types[0]
        let method = container.members.first { $0.name == "cannotOverride" }
        #expect(method?.modifiers.contains(.final) == true)
    }

    // MARK: - Default Parameter Tests

    @Test func defaultParameters() {
        let source = """
        class Config {
            fun connect(host: String = "localhost", port: Int = 8080) {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "Config.kt")
        let config = artifact.types[0]
        let method = config.members.first { $0.name == "connect" }
        #expect(method?.parameters.count == 2)
        #expect(method?.parameters[0].defaultValue != nil)
        #expect(method?.parameters[1].defaultValue != nil)
    }

    // MARK: - Complex Type Tests

    @Test func nestedGenericTypes() {
        let source = """
        class Store {
            val items: Map<String, List<Item>> = emptyMap()
        }
        """
        let artifact = parser.parse(source: source, fileName: "Store.kt")
        let store = artifact.types[0]
        let prop = store.members.first { $0.name == "items" }
        #expect(prop?.type?.genericArguments.count == 2)
    }

    @Test func multipleInheritance() {
        let source = """
        class Handler : EventListener, Serializable, Closeable {
            override fun close() {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "Handler.kt")
        let handler = artifact.types[0]
        #expect(handler.inheritedTypes.count >= 3)
        #expect(artifact.relationships.count >= 3)
    }

    // MARK: - Primary Constructor Visibility Tests

    @Test func primaryConstructorProperties() {
        let source = """
        class Person(
            val firstName: String,
            var lastName: String,
            age: Int
        ) {
            val fullName: String = "$firstName $lastName"
        }
        """
        let artifact = parser.parse(source: source, fileName: "Person.kt")
        let person = artifact.types[0]
        let firstName = person.members.first { $0.name == "firstName" }
        #expect(firstName?.kind == .property)
        let lastName = person.members.first { $0.name == "lastName" }
        #expect(lastName?.kind == .property)
        #expect(person.members.contains { $0.kind == .initializer })
    }

    // MARK: - Value Class Tests

    @Test func valueClass() {
        let source = """
        @JvmInline
        value class UserId(val value: String)
        """
        let artifact = parser.parse(source: source, fileName: "UserId.kt")
        let userId = artifact.types[0]
        #expect(userId.modifiers.contains(.inline) == true)
    }
}
