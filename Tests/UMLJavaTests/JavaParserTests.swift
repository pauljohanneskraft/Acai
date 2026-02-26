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

    @Test func modifiersStatic() {
        let source = """
        public class Utils {
            public static String CONSTANT = "value";
            public static void staticMethod() {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "Utils.java")
        let utils = artifact.types[0]

        let constant = utils.members.first { $0.name == "CONSTANT" }
        #expect(constant?.modifiers.contains(.static) == true)

        let method = utils.members.first { $0.name == "staticMethod" }
        #expect(method?.modifiers.contains(.static) == true)
    }

    @Test func modifiersFinal() {
        let source = """
        public final class Immutable {
            private final String value;
            public final void finalMethod() {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "Immutable.java")
        let immutable = artifact.types[0]
        #expect(immutable.modifiers.contains(.final) == true)

        let field = immutable.members.first { $0.name == "value" }
        #expect(field?.modifiers.contains(.final) == true)

        let method = immutable.members.first { $0.name == "finalMethod" }
        #expect(method?.modifiers.contains(.final) == true)
    }

    @Test func modifiersAbstract() {
        let source = """
        public abstract class AbstractBase {
            public abstract void abstractMethod();
            public void concreteMethod() {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "AbstractBase.java")
        let base = artifact.types[0]
        #expect(base.modifiers.contains(.abstract) == true)

        let abstractMethod = base.members.first { $0.name == "abstractMethod" }
        #expect(abstractMethod?.modifiers.contains(.abstract) == true)

        let concreteMethod = base.members.first { $0.name == "concreteMethod" }
        #expect(concreteMethod?.modifiers.contains(.abstract) == false)
    }

    @Test func modifiersSynchronized() {
        let source = """
        public class ThreadSafe {
            public synchronized void syncMethod() {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "ThreadSafe.java")
        let threadSafe = artifact.types[0]
        let method = threadSafe.members.first { $0.name == "syncMethod" }
        #expect(method?.modifiers.contains(.synchronized) == true)
    }

    @Test func modifiersVolatile() {
        let source = """
        public class Concurrent {
            private volatile boolean flag;
        }
        """
        let artifact = parser.parse(source: source, fileName: "Concurrent.java")
        let concurrent = artifact.types[0]
        let field = concurrent.members.first { $0.name == "flag" }
        #expect(field?.modifiers.contains(.volatile) == true)
    }

    @Test func modifiersTransient() {
        let source = """
        public class Serialization {
            private transient String tempData;
        }
        """
        let artifact = parser.parse(source: source, fileName: "Serialization.java")
        let serialization = artifact.types[0]
        let field = serialization.members.first { $0.name == "tempData" }
        #expect(field?.modifiers.contains(.transient) == true)
    }

    @Test func modifiersNative() {
        let source = """
        public class NativeLib {
            public native void nativeMethod();
        }
        """
        let artifact = parser.parse(source: source, fileName: "NativeLib.java")
        let nativeLib = artifact.types[0]
        let method = nativeLib.members.first { $0.name == "nativeMethod" }
        #expect(method?.modifiers.contains(.native) == true)
    }

    @Test func modifiersStrictfp() {
        let source = """
        public strictfp class StrictFloatingPoint {
            public strictfp void strictMethod() {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "StrictFloatingPoint.java")
        let strictClass = artifact.types[0]
        #expect(strictClass.modifiers.contains(.strictfp) == true)

        let method = strictClass.members.first { $0.name == "strictMethod" }
        #expect(method?.modifiers.contains(.strictfp) == true)
    }

    @Test func modifiersDefault() {
        let source = """
        public interface DefaultMethods {
            default void defaultMethod() {
                System.out.println("default");
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "DefaultMethods.java")
        let iface = artifact.types[0]
        let method = iface.members.first { $0.name == "defaultMethod" }
        #expect(method?.modifiers.contains(.default) == true)
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
        #expect(numbers?.type?.name.contains("[") == true)

        let matrix = arrays.members.first { $0.name == "matrix" }
        #expect(matrix?.type?.name.contains("[") == true)
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

    @Test func annotationType() {
        let source = """
        public @interface CustomAnnotation {
            String value();
            int priority() default 0;
        }
        """
        let artifact = parser.parse(source: source, fileName: "CustomAnnotation.java")
        #expect(artifact.types.count == 1)
        let annotation = artifact.types[0]
        #expect(annotation.kind == .annotation)
        #expect(annotation.members.count >= 1)
    }

    @Test func enumWithArguments() {
        let source = """
        public enum Planet {
            EARTH(5.976e+24, 6.37814e6),
            MARS(6.421e+23, 3.3972e6);

            private final double mass;
            private final double radius;

            Planet(double mass, double radius) {
                this.mass = mass;
                this.radius = radius;
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Planet.java")
        let planet = artifact.types[0]
        #expect(planet.kind == .enum)
        #expect(planet.enumCases.count == 2)
        #expect(planet.enumCases[0].name == "EARTH")
        #expect(planet.enumCases[1].name == "MARS")
    }

    @Test func enumWithInterfaces() {
        let source = """
        public enum Operation implements Calculator {
            ADD, SUBTRACT, MULTIPLY, DIVIDE;
        }
        """
        let artifact = parser.parse(source: source, fileName: "Operation.java")
        let operation = artifact.types[0]
        #expect(operation.kind == .enum)

        let conformance = artifact.relationships.first { $0.kind == .conformance }
        #expect(conformance != nil)
        #expect(conformance?.target == "Calculator")
    }

    @Test func recordWithInterfaces() {
        let source = """
        public record Coordinate(double x, double y) implements Comparable<Coordinate> {}
        """
        let artifact = parser.parse(source: source, fileName: "Coordinate.java")
        let coordinate = artifact.types[0]
        #expect(coordinate.kind == .record)

        let conformance = artifact.relationships.first { $0.kind == .conformance }
        #expect(conformance != nil)
        #expect(conformance?.target.contains("Comparable") == true)
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

    @Test func interfaceExtends() {
        let source = """
        public interface ExtendedRepository extends Repository, Serializable {
        }
        """
        let artifact = parser.parse(source: source, fileName: "ExtendedRepository.java")

        let conformances = artifact.relationships.filter { $0.kind == .conformance }
        #expect(conformances.count == 2)
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

    @Test func accessLevels() {
        let source = """
        public class AccessLevels {
            public String publicField;
            private String privateField;
            protected String protectedField;
            String packagePrivateField;
        }
        """
        let artifact = parser.parse(source: source, fileName: "AccessLevels.java")
        let accessLevels = artifact.types[0]

        let publicField = accessLevels.members.first { $0.name == "publicField" }
        #expect(publicField?.accessLevel == .public)

        let privateField = accessLevels.members.first { $0.name == "privateField" }
        #expect(privateField?.accessLevel == .private)

        let protectedField = accessLevels.members.first { $0.name == "protectedField" }
        #expect(protectedField?.accessLevel == .protected)

        let packagePrivate = accessLevels.members.first { $0.name == "packagePrivateField" }
        #expect(packagePrivate?.accessLevel == .packagePrivate)
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

    @Test func recordWithGenerics() {
        let source = """
        public record Box<T>(T value) {}
        """
        let artifact = parser.parse(source: source, fileName: "Box.java")
        let box = artifact.types[0]
        #expect(box.kind == .record)
        #expect(box.genericParameters.count == 1)
        #expect(box.members.count >= 1)
    }
}
