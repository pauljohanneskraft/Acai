import Testing
@testable import UMLJava
@testable import UMLCore

@Suite("Java Parser Tests")
struct JavaParserTests {
    let parser = JavaCodeParser()

    @Test func classInheritance() {
        let source = """
        package com.example;

        public class Dog extends Animal implements Serializable {
            private String breed;
        }
        """
        let artifact = parser.parse(source: source, fileName: "Dog.java")
        #expect(artifact.types.count == 1)
        let dog = artifact.types[0]
        #expect(dog.name == "Dog")
        #expect(dog.id == "com.example.Dog")
        #expect(dog.namespace == "com.example")

        let inheritance = artifact.relationships.first { $0.kind == .inheritance }
        #expect(inheritance != nil)
        #expect(inheritance?.source == "com.example.Dog")
        #expect(inheritance?.target == "Animal")

        let conformance = artifact.relationships.first { $0.kind == .conformance }
        #expect(conformance != nil)
        #expect(conformance?.target == "Serializable")
    }

    @Test func interfaceDeclaration() {
        let source = """
        public interface Repository<T> {
            T findById(String id);
            List<T> findAll();
        }
        """
        let artifact = parser.parse(source: source, fileName: "Repository.java")
        #expect(artifact.types.count == 1)
        let repo = artifact.types[0]
        #expect(repo.kind == .interface)
        #expect(repo.genericParameters.count == 1)
        #expect(repo.members.count == 2)
    }

    @Test func enumDeclaration() {
        let source = """
        public enum Direction {
            NORTH, SOUTH, EAST, WEST;
        }
        """
        let artifact = parser.parse(source: source, fileName: "Direction.java")
        #expect(artifact.types.count == 1)
        let dir = artifact.types[0]
        #expect(dir.kind == .enum)
        #expect(dir.enumCases.count == 4)
        #expect(dir.enumCases[0].name == "NORTH")
    }

    @Test func fieldDeclaration() {
        let source = """
        public class Config {
            private String name;
            public int count;
            private List<String> items;
        }
        """
        let artifact = parser.parse(source: source, fileName: "Config.java")
        let config = artifact.types[0]
        let nameField = config.members.first { $0.name == "name" }
        #expect(nameField?.type?.name == "String")
        #expect(nameField?.accessLevel == .private)

        let countField = config.members.first { $0.name == "count" }
        #expect(countField?.type?.name == "int")
        #expect(countField?.accessLevel == .public)
    }

    @Test func methodDeclaration() {
        let source = """
        public class Service {
            public String process(int id, String name) {
                return name;
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Service.java")
        let service = artifact.types[0]
        let method = service.members.first { $0.name == "process" }
        #expect(method?.kind == .method)
        #expect(method?.type?.name == "String")
        #expect(method?.parameters.count == 2)
    }

    @Test func recordDeclaration() {
        let source = """
        public record Point(int x, int y) {}
        """
        let artifact = parser.parse(source: source, fileName: "Point.java")
        #expect(artifact.types.count == 1)
        let point = artifact.types[0]
        #expect(point.kind == .record)
        #expect(point.members.count >= 2) // x and y as properties
    }

    @Test func nestedClasses() {
        let source = """
        public class Outer {
            public class Inner {
                private String value;
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Outer.java")
        #expect(artifact.types.count == 1)
        let outer = artifact.types[0]
        #expect(outer.nestedTypes.count == 1)
        #expect(outer.nestedTypes[0].name == "Inner")
    }
}
