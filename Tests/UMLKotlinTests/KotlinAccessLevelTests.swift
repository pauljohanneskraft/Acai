import Testing
@testable import UMLKotlin
@testable import UMLCore

@Suite("Kotlin Access Level & Modifier Tests")
struct KotlinAccessLevelTests {
    let parser = KotlinCodeParser()

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
}
