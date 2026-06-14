import Testing
import UMLCore
import UMLDiagram
import UMLDart
import UMLKotlin
import UMLLibrary
import UMLSwift

@Suite("UML Library Tests")
struct UMLLibraryTests {
    @Test func parseErrorsAggregateAcrossMergedFiles() async throws {
        let parser = KotlinCodeParser()
        let cleanSource = """
        class Ok(val name: String) {
            fun greet(): String {
                return name
            }
        }
        """
        let clean = parser.parse(source: cleanSource, fileName: "Ok.kt")
        let broken = parser.parse(source: "class Broken { fun (", fileName: "Bad.kt")
        #expect(clean.metadata.hasParseErrors == false)
        #expect(broken.metadata.hasParseErrors == true)
        // A single malformed file must flag the whole merged project, regardless of merge order.
        #expect(clean.merging(with: broken).metadata.hasParseErrors == true)
        #expect(broken.merging(with: clean).metadata.hasParseErrors == true)
    }

    @Test func testKotlin() async throws {
        let source = """
        sealed class SuperClass {
            object SubClass1 : SuperClass()
            data class SubClass2(val property1: String): SuperClass()
        }
        """
        let artifact = KotlinCodeParser().parse(source: source, fileName: "Source.kt")
        let diagram = DOTGenerator().generate(from: artifact)
        print(diagram)
    }

    @Test func testSwift() async throws {
        let source = """
        enum SuperClass {
            case subClass1(SubClass1)
            case subClass2(SubClass2)
            struct SubClass1 {}
            struct SubClass2 {
                let property1: String
            }
        }
        """
        let artifact = SwiftCodeParser().parse(source: source, fileName: "Source.swift")
        print(artifact)
        let diagram = DOTGenerator().generate(from: artifact)
        print(diagram)
    }

    @Test func testDartBasicClass() async throws {
        let source = """
        class User {
            String name;
            int age;

            User(this.name, this.age);

            String describe() {
                return 'User: $name, age $age';
            }
        }
        """
        let artifact = DartCodeParser().parse(source: source, fileName: "User.dart")
        let diagram = DOTGenerator().generate(from: artifact)
        print(diagram)
        #expect(diagram.contains("User"))
        #expect(diagram.contains("name"))
        #expect(diagram.contains("age"))
    }

    @Test func testDartInheritance() async throws {
        let source = """
        abstract class Animal {
            String name;
            void makeSound();
        }

        class Dog extends Animal {
            String breed;

            void makeSound() {
                print('Woof!');
            }
        }
        """
        let artifact = DartCodeParser().parse(source: source, fileName: "Animal.dart")
        let diagram = DOTGenerator().generate(from: artifact)
        print(diagram)
        #expect(diagram.contains("Animal"))
        #expect(diagram.contains("Dog"))
        #expect(artifact.relationships.count >= 1)
    }

    @Test func testDartMixinAndInterface() async throws {
        let source = """
        mixin Flyable {
            void fly() {
                print('Flying');
            }
        }

        abstract class Serializable {
            String toJson();
        }

        class Bird extends Animal with Flyable implements Serializable {
            String species;

            String toJson() => '{"species": "$species"}';
        }

        class Animal {
            String name;
        }
        """
        let artifact = DartCodeParser().parse(source: source, fileName: "Bird.dart")
        let diagram = DOTGenerator().generate(from: artifact)
        print(diagram)
        #expect(diagram.contains("Bird"))
        #expect(diagram.contains("Flyable"))
        #expect(diagram.contains("Serializable"))
        #expect(artifact.relationships.count >= 3)
    }

    @Test func testDartEnum() async throws {
        let source = """
        enum Status {
            pending,
            active,
            completed,
            cancelled;

            bool get isFinished => this == completed || this == cancelled;
        }
        """
        let artifact = DartCodeParser().parse(source: source, fileName: "Status.dart")
        let diagram = DOTGenerator().generate(from: artifact)
        print(diagram)
        #expect(diagram.contains("Status"))
        #expect(artifact.types[0].enumCases.count == 4)
    }

    @Test func testDartGenerics() async throws {
        let source = """
        class Box<T> {
            T value;

            Box(this.value);

            T getValue() => value;
        }

        class Pair<K, V> {
            K key;
            V value;

            Pair(this.key, this.value);
        }
        """
        let artifact = DartCodeParser().parse(source: source, fileName: "Generics.dart")
        let diagram = DOTGenerator().generate(from: artifact)
        print(diagram)
        #expect(diagram.contains("Box"))
        #expect(diagram.contains("Pair"))
        #expect(artifact.types.count == 2)
    }

    @Test func testDartExtension() async throws {
        let source = """
        extension StringExtension on String {
            bool get isBlank => trim().isEmpty;

            String capitalize() {
                if (isEmpty) return this;
                return this[0].toUpperCase() + substring(1);
            }
        }
        """
        let artifact = DartCodeParser().parse(source: source, fileName: "StringExt.dart")
        let diagram = DOTGenerator().generate(from: artifact)
        print(diagram)
        #expect(artifact.types.count >= 1)
        let ext = artifact.types.first { $0.kind == .extension }
        #expect(ext != nil)
    }
}
