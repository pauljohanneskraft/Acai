import Testing
@testable import UMLJVM
@testable import UMLCore

@Suite("Java: Class Tests")
struct JavaClassTests {
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

    @Test func staticNestedClass() {
        let source = """
        public class Outer {
            public static class StaticNested {
                private int value;
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Outer.java")
        let outer = artifact.types[0]
        #expect(outer.nestedTypes.count == 1)
        let nested = outer.nestedTypes[0]
        #expect(nested.modifiers.contains(.static) == true)
    }

    @Test func multipleInheritance() {
        let source = """
        public class Dog extends Animal implements Runnable, Comparable<Dog> {
        }
        """
        let artifact = parser.parse(source: source, fileName: "Dog.java")

        let inheritance = artifact.relationships.filter { $0.kind == .inheritance }
        #expect(inheritance.count == 1)
        #expect(inheritance[0].target == "Animal")

        let conformances = artifact.relationships.filter { $0.kind == .conformance }
        #expect(conformances.count >= 2)
    }

    @Test func annotations() {
        let source = """
        @Deprecated
        @SuppressWarnings("unchecked")
        public class AnnotatedClass {
            @Override
            public String toString() {
                return "test";
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "AnnotatedClass.java")
        let annotatedClass = artifact.types[0]
        #expect(annotatedClass.annotations.count >= 1)
        #expect(annotatedClass.annotations.contains { $0.contains("Deprecated") })
    }

    @Test func genericConstraints() {
        let source = """
        public class Container<T extends Comparable<T> & Serializable> {
            private T value;
        }
        """
        let artifact = parser.parse(source: source, fileName: "Container.java")
        let container = artifact.types[0]
        #expect(container.genericParameters.count == 1)
        let param = container.genericParameters[0]
        #expect(param.name == "T")
        #expect(param.constraints.count >= 1)
    }

    @Test func multipleGenericParameters() {
        let source = """
        public class Pair<K extends Comparable<K>, V> {
            private K key;
            private V value;
        }
        """
        let artifact = parser.parse(source: source, fileName: "Pair.java")
        let pair = artifact.types[0]
        #expect(pair.genericParameters.count == 2)
        #expect(pair.genericParameters[0].name == "K")
        #expect(pair.genericParameters[1].name == "V")
    }

    @Test func constructorWithParameters() {
        let source = """
        public class Person {
            private String name;
            private int age;

            public Person(String name, int age) {
                this.name = name;
                this.age = age;
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Person.java")
        let person = artifact.types[0]
        let constructor = person.members.first { $0.kind == .initializer }
        #expect(constructor != nil)
        #expect(constructor?.parameters.count == 2)
        #expect(constructor?.parameters[0].internalName == "name")
        #expect(constructor?.parameters[1].internalName == "age")
    }

    @Test func arrayTypes() {
        let source = """
        public class Arrays {
            private int[] numbers;
            private String[][] matrix;
        }
        """
        let artifact = parser.parse(source: source, fileName: "Arrays.java")
        let arrays = artifact.types[0]
        let numbers = arrays.members.first { $0.name == "numbers" }
        #expect(numbers?.type?.isArray == true)
        #expect(numbers?.type?.name == "int")

        let matrix = arrays.members.first { $0.name == "matrix" }
        #expect(matrix?.type?.isArray == true)
        #expect(matrix?.type?.name == "String")
    }

    @Test func wildcardTypes() {
        let source = """
        public class Wildcards {
            private List<?> anything;
            private List<? extends Number> numbers;
            private List<? super Integer> integers;
        }
        """
        let artifact = parser.parse(source: source, fileName: "Wildcards.java")
        let wildcards = artifact.types[0]
        #expect(wildcards.members.count == 3)

        let anything = wildcards.members.first { $0.name == "anything" }
        #expect(anything?.type != nil)
    }

    @Test func varargParameter() {
        let source = """
        public class VarArgs {
            public void method(String first, int... numbers) {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "VarArgs.java")
        let varArgs = artifact.types[0]
        let method = varArgs.members.first { $0.name == "method" }
        #expect(method?.parameters.count == 2)
        #expect(method?.parameters[1].internalName == "numbers")
        #expect(method?.parameters[1].isVariadic == true)
    }

     @Test func multipleFieldDeclarators() {
        let source = """
        public class MultiField {
            private int x, y, z;
            public String a, b;
        }
        """
        let artifact = parser.parse(source: source, fileName: "MultiField.java")
        let multiField = artifact.types[0]
        #expect(multiField.members.count >= 5)

        let x = multiField.members.first { $0.name == "x" }
        let y = multiField.members.first { $0.name == "y" }
        let z = multiField.members.first { $0.name == "z" }
        #expect(x?.type?.name == "int")
        #expect(y?.type?.name == "int")
        #expect(z?.type?.name == "int")
    }

    @Test func packageNamespace() {
        let source = """
        package com.example.project;

        public class MyClass {}
        """
        let artifact = parser.parse(source: source, fileName: "MyClass.java")
        let myClass = artifact.types[0]
        #expect(myClass.namespace == "com.example.project")
        #expect(myClass.qualifiedName == "com.example.project.MyClass")
        #expect(myClass.id == "com.example.project.MyClass")
    }

    @Test func complexGenerics() {
        let source = """
        public class Complex {
            private Map<String, List<Integer>> data;
            private Function<String, Optional<User>> mapper;
        }
        """
        let artifact = parser.parse(source: source, fileName: "Complex.java")
        let complex = artifact.types[0]
        #expect(complex.members.count == 2)

        let data = complex.members.first { $0.name == "data" }
        #expect(data?.type?.name == "Map")
    }

    @Test func genericMethods() {
        let source = """
        public class GenericMethods {
            public <T> T identity(T value) {
                return value;
            }

            public <T extends Comparable<T>> T max(T a, T b) {
                return a;
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "GenericMethods.java")
        let genericMethods = artifact.types[0]
        #expect(genericMethods.members.count == 2)

        let identity = genericMethods.members.first { $0.name == "identity" }
        #expect(identity?.genericParameters.count == 1)

        let max = genericMethods.members.first { $0.name == "max" }
        #expect(max?.genericParameters.count == 1)
    }

    @Test func overloadedMethods() {
        let source = """
        public class Overloaded {
            public void method() {}
            public void method(int x) {}
            public void method(String s) {}
            public void method(int x, String s) {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "Overloaded.java")
        let overloaded = artifact.types[0]
        let methods = overloaded.members.filter { $0.name == "method" }
        #expect(methods.count == 4)
    }

    @Test func overloadedConstructors() {
        let source = """
        public class MultiConstructor {
            public MultiConstructor() {}
            public MultiConstructor(int x) {}
            public MultiConstructor(String s) {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "MultiConstructor.java")
        let multiConstructor = artifact.types[0]
        let constructors = multiConstructor.members.filter { $0.kind == .initializer }
        #expect(constructors.count == 3)
    }

    @Test func throwsClause() {
        let source = """
        public class Exceptions {
            public void riskyMethod() throws IOException, SQLException {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "Exceptions.java")
        let exceptions = artifact.types[0]
        let method = exceptions.members.first { $0.name == "riskyMethod" }
        #expect(method != nil)
    }

}
