import Testing
@testable import AcaiSwift
@testable import AcaiCore

@Suite("Swift Field-Read Extraction")
struct SwiftFieldReadTests {
    let parser = SwiftCodeParser()

    private func member(_ name: String, in source: String) -> Member? {
        let artifact = parser.parse(source: source, fileName: "Test.swift")
        return artifact.types.first?.members.first { $0.name == name }
    }

    @Test func bareAndSelfQualifiedReadsAreCaptured() {
        // Reads are captured in expression position. (Like call sites, the Swift extractor skips local
        // `let`/`var` declarations inside a body, so reads in a local's initializer aren't captured —
        // a pre-existing limitation shared with call-site extraction, not specific to reads.)
        let source = """
        class Counter {
            var total: Int = 0
            var label: String = ""
            func describe() -> String {
                return self.label + String(total)
            }
        }
        """
        let reads = member("describe", in: source)?.fieldReads ?? []
        let names = Set(reads.map(\.name))
        #expect(names.contains("total"))   // bare identifier read
        #expect(names.contains("label"))   // self-qualified read
        #expect(reads.allSatisfy { $0.receiver == nil })
    }

    @Test func nonPropertyIdentifiersAreNotCaptured() {
        // Parameters that don't name a stored property must not surface as field reads.
        let source = """
        class Counter {
            var total: Int = 0
            func add(delta: Int) -> Int {
                return delta
            }
        }
        """
        let reads = member("add", in: source)?.fieldReads ?? []
        #expect(reads.isEmpty)
    }

    @Test func explicitAndBareSelfCallsBothRecordAsSelfDispatch() {
        // Both `self.helper()` and a bare `helper()` are recorded as `.selfDispatch`; the parser can't
        // tell an implicit-self method call from a free function at single-file parse time, so it emits
        // the optimistic receiver and the whole-artifact resolvers disambiguate self vs. free.
        let source = """
        class Worker {
            func run() {
                self.helper()
                other()
            }
            func helper() {}
            func other() {}
        }
        """
        let calls = member("run", in: source)?.callSites ?? []
        #expect(calls.contains { $0.methodName == "helper" && $0.receiver == .selfDispatch })
        #expect(calls.contains { $0.methodName == "other" && $0.receiver == .selfDispatch })
    }
}
