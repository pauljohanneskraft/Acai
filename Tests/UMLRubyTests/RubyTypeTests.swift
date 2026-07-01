import Testing
@testable import UMLCore
@testable import UMLRuby

@Suite("Ruby: Type Tests")
struct RubyTypeTests {
    let parser = RubyCodeParser()

    @Test func classInheritanceAndMethods() {
        let source = """
        class Animal
          def speak(volume = 1)
          end
        end

        class Dog < Animal
          def initialize(name)
            @name = name
          end

          def self.create
            new("Fido")
          end
        end
        """

        let artifact = parser.parse(source: source, fileName: "animal.rb")
        #expect(artifact.types.count == 2)

        let dog = artifact.types.first { $0.name == "Dog" }
        #expect(dog?.inheritedTypes.map(\.name) == ["Animal"])
        #expect(artifact.relationships.contains {
            $0.kind == .inheritance && $0.source == "Dog" && $0.target == "Animal"
        })

        let initializer = dog?.members.first { $0.kind == .initializer }
        #expect(initializer?.name == "initialize")
        #expect(initializer?.parameters.map(\.internalName) == ["name"])

        let staticFactory = dog?.members.first { $0.name == "create" }
        #expect(staticFactory?.modifiers.contains(.static) == true)
    }

    @Test func nestedModuleAndClassNamesAreQualified() {
        let source = """
        module Services
          class UserService
            def call
            end
          end
        end
        """

        let artifact = parser.parse(source: source, fileName: "services.rb")
        #expect(artifact.types.count == 1)
        let services = artifact.types.first
        let nested = services?.nestedTypes.first

        #expect(services?.kind == .module)
        #expect(services?.id == "Services")
        #expect(nested?.name == "UserService")
        #expect(nested?.id == "Services.UserService")
    }
}
