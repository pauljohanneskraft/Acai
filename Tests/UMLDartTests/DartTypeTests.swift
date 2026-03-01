import Testing
@testable import UMLDart
@testable import UMLCore

@Suite("Dart: Type Tests")
struct DartTypeTests {
    let parser = DartCodeParser()

    @Test func classDeclaration() {
        let source = """
        class User {
            String name;
            int age;
        }
        """
        let artifact = parser.parse(source: source, fileName: "User.dart")
        #expect(artifact.types.count == 1)
        let user = artifact.types[0]
        #expect(user.name == "User")
        #expect(user.kind == .class)
        #expect(user.members.count == 2)
    }

    @Test func abstractClass() {
        let source = """
        abstract class Shape {
            double area();
            String describe() {
                return "Shape";
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Shape.dart")
        let shape = artifact.types[0]
        #expect(shape.modifiers.contains(.abstract))
        #expect(shape.members.count >= 1)
    }

    @Test func interfaceDeclaration() {
        let source = """
        abstract interface class Repository {
            Entity findById(String id);
            List<Entity> findAll();
        }
        """
        let artifact = parser.parse(source: source, fileName: "Repository.dart")
        #expect(artifact.types.count == 1)
        let repo = artifact.types[0]
        #expect(repo.kind == .class)
        #expect(repo.modifiers.contains(.abstract))
    }

    @Test func enumDeclaration() {
        let source = """
        enum Direction {
            north,
            south,
            east,
            west
        }
        """
        let artifact = parser.parse(source: source, fileName: "Direction.dart")
        #expect(artifact.types.count == 1)
        let dir = artifact.types[0]
        #expect(dir.kind == .enum)
        #expect(dir.enumCases.count == 4)
        #expect(dir.enumCases[0].name == "north")
        #expect(dir.enumCases[1].name == "south")
    }

    @Test func mixinDeclaration() {
        let source = """
        mixin Flyable {
            void fly() {
                print('Flying');
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Flyable.dart")
        #expect(artifact.types.count == 1)
        let mixin = artifact.types[0]
        #expect(mixin.kind == .mixin)
        #expect(mixin.name == "Flyable")
    }

    @Test func extensionDeclaration() {
        let source = """
        extension StringExtension on String {
            bool get isBlank => trim().isEmpty;
            String capitalize() => this[0].toUpperCase() + substring(1);
        }
        """
        let artifact = parser.parse(source: source, fileName: "StringExt.dart")
        #expect(artifact.types.count == 1)
        let ext = artifact.types[0]
        #expect(ext.kind == .extension)
        #expect(ext.extensionOf == "String")
    }

    // MARK: - Relationships

    @Test func classInheritance() {
        let source = """
        class Animal {
            String name;
        }

        class Dog extends Animal {
            String breed;
        }
        """
        let artifact = parser.parse(source: source, fileName: "Animals.dart")
        #expect(artifact.types.count == 2)

        let dog = artifact.types.first { $0.name == "Dog" }
        #expect(dog != nil)
        #expect(dog?.inheritedTypes.count == 1)

        let inheritance = artifact.relationships.first { $0.kind == .inheritance }
        #expect(inheritance?.source == "Dog")
        #expect(inheritance?.target == "Animal")
    }

    @Test func classImplementsInterface() {
        let source = """
        abstract class Serializable {
            String toJson();
        }

        class User implements Serializable {
            String name;
            String toJson() => '{}';
        }
        """
        let artifact = parser.parse(source: source, fileName: "User.dart")
        #expect(artifact.types.count == 2)

        let conformance = artifact.relationships.first { $0.kind == .conformance }
        #expect(conformance?.source == "User")
        #expect(conformance?.target == "Serializable")
    }

    @Test func classWithMixin() {
        let source = """
        mixin Flyable {
            void fly() {}
        }

        class Bird with Flyable {
            String species;
        }
        """
        let artifact = parser.parse(source: source, fileName: "Bird.dart")
        #expect(artifact.types.count == 2)

        let bird = artifact.types.first { $0.name == "Bird" }
        #expect(bird != nil)

        let mixinRel = artifact.relationships.first {
            $0.kind == .inheritance && $0.source == "Bird" && $0.target == "Flyable"
        }
        #expect(mixinRel != nil)
    }

    @Test func complexInheritance() {
        let source = """
        class Animal {
            String name;
        }

        mixin Flyable {
            void fly() {}
        }

        abstract class Serializable {
            String toJson();
        }

        class Bird extends Animal with Flyable implements Serializable {
            String species;
            String toJson() => '{}';
        }
        """
        let artifact = parser.parse(source: source, fileName: "Bird.dart")
        #expect(artifact.types.count == 4)

        let bird = artifact.types.first { $0.name == "Bird" }
        #expect(bird != nil)
        #expect(bird?.inheritedTypes.count == 3)

        let relationships = artifact.relationships.filter { $0.source == "Bird" }
        #expect(relationships.count == 3)

        let inheritance = relationships.first { $0.kind == .inheritance && $0.target == "Animal" }
        #expect(inheritance != nil)

        let mixinRel = relationships.first { $0.kind == .inheritance && $0.target == "Flyable" }
        #expect(mixinRel != nil)

        let conformance = relationships.first { $0.kind == .conformance && $0.target == "Serializable" }
        #expect(conformance != nil)
    }

    @Test func enumImplementsInterface() {
        let source = """
        abstract class Displayable {
            String display();
        }

        enum Color implements Displayable {
            red,
            green,
            blue;

            String display() => name;
        }
        """
        let artifact = parser.parse(source: source, fileName: "Color.dart")
        let color = artifact.types.first { $0.name == "Color" }
        #expect(color?.kind == .enum)
        #expect(color?.enumCases.count == 3)

        let conformance = artifact.relationships.first { $0.kind == .conformance }
        #expect(conformance?.target == "Displayable")
    }

    // MARK: - Generics

    @Test func genericClass() {
        let source = """
        class Box<T> {
            T value;
            Box(this.value);
        }
        """
        let artifact = parser.parse(source: source, fileName: "Box.dart")
        let box = artifact.types[0]
        #expect(box.genericParameters.count == 1)
        #expect(box.genericParameters[0].name == "T")
    }

    @Test func genericClassWithConstraint() {
        let source = """
        class Container<T extends Comparable> {
            T item;
        }
        """
        let artifact = parser.parse(source: source, fileName: "Container.dart")
        let container = artifact.types[0]
        #expect(container.genericParameters.count == 1)
        #expect(container.genericParameters[0].name == "T")
    }

    @Test func multipleGenericParameters() {
        let source = """
        class Pair<K, V> {
            K key;
            V value;
        }
        """
        let artifact = parser.parse(source: source, fileName: "Pair.dart")
        let pair = artifact.types[0]
        #expect(pair.genericParameters.count == 2)
        #expect(pair.genericParameters[0].name == "K")
        #expect(pair.genericParameters[1].name == "V")
    }

    // MARK: - Members

    @Test func fieldDeclarations() {
        let source = """
        class Config {
            String name;
            int count;
            double? ratio;
            final String id;
            static const String version = '1.0';
        }
        """
        let artifact = parser.parse(source: source, fileName: "Config.dart")
        let config = artifact.types[0]
        #expect(config.members.count >= 3)

        let nameField = config.members.first { $0.name == "name" }
        #expect(nameField?.type?.name == "String")

        let ratioField = config.members.first { $0.name == "ratio" }
        #expect(ratioField?.type?.isOptional == true)
    }

    @Test func nestedClasses() {
        // Dart does not support nested class definitions.
        // tree-sitter-dart produces ERROR nodes for this pattern.
        let source = """
        class Outer {
            String outerField;

            class Inner {
                String innerField;
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Outer.dart")
        let outer = artifact.types[0]
        #expect(outer.nestedTypes.isEmpty)
    }

    @Test func libraryDeclaration() {
        let source = """
        library my.library;

        class MyClass {
            String value;
        }
        """
        let artifact = parser.parse(source: source, fileName: "MyClass.dart")
        let myClass = artifact.types[0]
        #expect(myClass.namespace == "my.library")
        #expect(myClass.id == "my.library.MyClass")
    }

    @Test func mixinOn() {
        let source = """
        class Animal {}

        mixin Walker on Animal {
            void walk() {
                print('Walking');
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Walker.dart")
        let walker = artifact.types.first { $0.name == "Walker" }
        #expect(walker?.kind == .mixin)

        let mixinConstraint = artifact.relationships.first {
            $0.source == "Walker" && $0.target == "Animal"
        }
        #expect(mixinConstraint != nil)
    }

}
