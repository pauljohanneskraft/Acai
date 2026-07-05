import Testing
@testable import UMLJVM
@testable import UMLCore

@Suite("Java Field-Read Extraction")
struct JavaFieldReadTests {
    let parser = JavaCodeParser()

    private func member(_ name: String, in source: String) -> Member? {
        let artifact = parser.parse(source: source, fileName: "Test.java")
        return artifact.types.first?.members.first { $0.name == name }
    }

    @Test func bareAndThisQualifiedReadsAreCaptured() {
        let source = """
        class Counter {
            private int total;
            private String label;
            String describe() {
                int sum = total + 1;
                return this.label;
            }
        }
        """
        let reads = member("describe", in: source)?.fieldReads ?? []
        let names = Set(reads.map(\.name))
        #expect(names.contains("total"))   // bare identifier read
        #expect(names.contains("label"))   // this-qualified read
        #expect(reads.allSatisfy { $0.receiver == nil })
    }

    @Test func nonPropertyIdentifiersAreNotCaptured() {
        let source = """
        class Counter {
            private int total;
            int add(int delta) {
                int scratch = delta + 1;
                return scratch;
            }
        }
        """
        let reads = member("add", in: source)?.fieldReads ?? []
        #expect(reads.isEmpty)
    }
}
