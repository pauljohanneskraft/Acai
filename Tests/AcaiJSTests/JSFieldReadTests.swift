import Testing
@testable import AcaiCore
@testable import AcaiJS

@Suite("JS Field-Read Extraction")
struct JSFieldReadTests {
    let parser = JSCodeParser()

    private func member(_ name: String, in source: String, fileName: String = "test.js") -> Member? {
        parser.parse(source: source, fileName: fileName).types.first?.members.first { $0.name == name }
    }

    @Test func bareAndThisQualifiedReadsAreCaptured() {
        let source = """
        class Counter {
            constructor() {
                this.total = 0;
                this.label = "";
            }
            describe() {
                const sum = this.total + 1;
                return this.label;
            }
        }
        """
        let reads = member("describe", in: source)?.fieldReads ?? []
        #expect(Set(reads.map(\.name)) == ["total", "label"])
        #expect(reads.allSatisfy { $0.receiver == nil })
    }

    @Test func aReadThroughAnotherObjectIsNotAnOwnFieldRead() {
        let source = """
        class Counter {
            constructor() {
                this.id = 0;
            }
            equals(o) {
                return o.id === 1;
            }
        }
        """
        #expect(member("equals", in: source)?.fieldReads.isEmpty == true)
    }

    @Test func optionalChainingThroughAnotherObjectIsNotAnOwnFieldRead() {
        let source = """
        class Counter {
            constructor() {
                this.id = 0;
            }
            equals(o) {
                return o?.id === this.id;
            }
        }
        """
        // Only the `this.id` read survives — `o?.id` belongs to `o`.
        #expect(member("equals", in: source)?.fieldReads.map(\.name) == ["id"])
    }
}
