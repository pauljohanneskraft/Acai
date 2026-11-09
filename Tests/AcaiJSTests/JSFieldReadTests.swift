import Testing
@testable import AcaiCore
@testable import AcaiJS

/// `JSCodeParser` serves TypeScript and JavaScript alike. The fixtures annotate their fields because
/// the extractor's class-body prepass only knows a property whose type it can determine, so an
/// unannotated field is invisible to field-read capture and would make these assertions vacuous.
@Suite("JS Field-Read Receivers")
struct JSFieldReadTests {
    let parser = JSCodeParser()

    private func member(_ name: String, in source: String) -> Member? {
        parser.parse(source: source, fileName: "counter.ts").types.first?.members.first { $0.name == name }
    }

    @Test func bareAndThisQualifiedReadsAreCaptured() {
        let source = """
        class Counter {
            total: number = 0;
            label: string = "";
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
            id: number = 0;
            equals(o: Counter) {
                return o.id === 1;
            }
        }
        """
        #expect(member("equals", in: source)?.fieldReads.isEmpty == true)
    }

    @Test func onlyTheSelfQualifiedHalfOfAComparisonIsCaptured() {
        let source = """
        class Counter {
            id: number = 0;
            equals(o: Counter) {
                return o?.id === this.id;
            }
        }
        """
        // `o?.id` belongs to `o`; only `this.id` is this type's own field.
        #expect(member("equals", in: source)?.fieldReads.map(\.name) == ["id"])
    }

    @Test func aReadOffALongerChainIsNotAnOwnFieldRead() {
        let source = """
        class Counter {
            id: number = 0;
            peer: Counter = new Counter();
            copy() {
                return this.peer.id;
            }
        }
        """
        // `this.peer` is an own read; `id` past it is the peer's field, not ours.
        #expect(member("copy", in: source)?.fieldReads.map(\.name) == ["peer"])
    }
}
