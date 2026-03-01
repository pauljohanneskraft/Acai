import Testing
@testable import UMLDart
@testable import UMLCore

@Suite("Dart: Other Tests")
struct DartOtherTests {
    let parser = DartCodeParser()

    @Test func methodDeclaration() {
        let source = """
        class Calculator {
            int add(int a, int b) {
                return a + b;
            }

            double divide(int a, int b) {
                return a / b;
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Calculator.dart")
        let calc = artifact.types[0]
        let addMethod = calc.members.first { $0.name == "add" }
        #expect(addMethod?.kind == .method)
        #expect(addMethod?.type?.name == "int")
        #expect(addMethod?.parameters.count == 2)
    }

    @Test func constructorDeclaration() {
        let source = """
        class Person {
            String name;
            int age;

            Person(this.name, this.age);

            Person.guest() : name = 'Guest', age = 0;
        }
        """
        let artifact = parser.parse(source: source, fileName: "Person.dart")
        let person = artifact.types[0]
        let constructors = person.members.filter { $0.kind == .initializer }
        #expect(constructors.count >= 1)
    }

    @Test func getterAndSetter() {
        let source = """
        class Rectangle {
            double width;
            double height;

            double get area => width * height;

            set dimensions(List<double> values) {
                width = values[0];
                height = values[1];
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Rectangle.dart")
        let rect = artifact.types[0]

        let getter = rect.members.first { $0.name == "area" }
        #expect(getter != nil)
        #expect(getter?.isComputed == true)
    }

    @Test func staticMembers() {
        let source = """
        class Math {
            static const double pi = 3.14159;
            static int square(int x) => x * x;
        }
        """
        let artifact = parser.parse(source: source, fileName: "Math.dart")
        let math = artifact.types[0]
        let staticMembers = math.members.filter { $0.modifiers.contains(.static) }
        #expect(staticMembers.count >= 1)
    }

    @Test func factoryConstructor() {
        let source = """
        class Logger {
            static Logger? _instance;

            factory Logger() {
                return _instance ??= Logger._internal();
            }

            Logger._internal();
        }
        """
        let artifact = parser.parse(source: source, fileName: "Logger.dart")
        let logger = artifact.types[0]
        let constructors = logger.members.filter { $0.kind == .initializer }
        #expect(constructors.count >= 1)
    }

    @Test func operatorOverload() {
        let source = """
        class Vector {
            double x, y;

            Vector operator +(Vector other) {
                return Vector(x + other.x, y + other.y);
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Vector.dart")
        let vector = artifact.types[0]
        let operatorMethod = vector.members.first { $0.name == "+" }
        #expect(operatorMethod != nil)
    }

    @Test func nullableTypes() {
        let source = """
        class Config {
            String? name;
            int count;
            List<String>? tags;
        }
        """
        let artifact = parser.parse(source: source, fileName: "Config.dart")
        let config = artifact.types[0]

        let nameField = config.members.first { $0.name == "name" }
        #expect(nameField?.type?.isOptional == true)

        let countField = config.members.first { $0.name == "count" }
        #expect(countField?.type?.isOptional == false)
    }

    @Test func freestandingFunction() {
        let source = """
        int add(int a, int b) {
            return a + b;
        }

        void printMessage(String msg) {
            print(msg);
        }
        """
        let artifact = parser.parse(source: source, fileName: "Utils.dart")
        #expect(artifact.freestandingFunctions.count >= 1)
        let addFunc = artifact.freestandingFunctions.first { $0.name == "add" }
        #expect(addFunc != nil)
        #expect(addFunc?.type?.name == "int")
    }

    @Test func extensionType() {
        let source = """
        extension type IdNumber(int id) {
            bool get isValid => id > 0;
        }
        """
        let artifact = parser.parse(source: source, fileName: "IdNumber.dart")
        #expect(artifact.types.count >= 1)
        let idNumber = artifact.types.first { $0.name == "IdNumber" }
        #expect(idNumber != nil)
    }
}
