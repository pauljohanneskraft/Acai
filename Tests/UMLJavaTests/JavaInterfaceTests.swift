import Testing
@testable import UMLJava
@testable import UMLCore

@Suite("Java: Interface Tests")
struct JavaInterfaceTests {
    let parser = JavaCodeParser()

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

    @Test func interfaceExtends() {
        let source = """
        public interface ExtendedRepository extends Repository, Serializable {
        }
        """
        let artifact = parser.parse(source: source, fileName: "ExtendedRepository.java")

        let conformances = artifact.relationships.filter { $0.kind == .conformance }
        #expect(conformances.count == 2)
    }

}
