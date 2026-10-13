import Testing
@testable import AcaiSwift
@testable import AcaiCore

@Suite("Swift: Subscript Call Sites")
struct SwiftSubscriptCallSiteTests {
    private func callSites(in source: String, method: String, ofType type: String = "Worker") -> [CallSite] {
        let artifact = SwiftCodeParser().parse(source: source, fileName: "\(type).swift")
        let decl = artifact.types.first { $0.name == type }
        return decl?.members.first { $0.name == method }?.callSites ?? []
    }

    @Test func capturesSubscriptAccessOnLocallyDeclaredType() {
        let sites = callSites(in: """
        class Thing {
            subscript(i: Int) -> Int { 0 }
            func run() {
                let made = Thing()
                _ = made[0]
                _ = self[1]
            }
        }
        """, method: "run", ofType: "Thing")
        let subscriptSites = sites.filter { $0.methodName == "subscript" }
        #expect(subscriptSites.count == 2)
        #expect(subscriptSites.contains { $0.receiverType == "Thing" })
        #expect(subscriptSites.contains { $0.receiver == .selfDispatch })
    }

    @Test func capturesSubscriptAccessOnATypeDeclaredInAnotherFile() {
        let sites = callSites(in: """
        class Worker {
            let matrix: Matrix
            func run() {
                _ = matrix[0]
                _ = Elsewhere()[1]
            }
        }
        """, method: "run")
        let receivers = sites.filter { $0.methodName == "subscript" }.compactMap(\.receiverType)
        #expect(receivers.sorted() == ["Elsewhere", "Matrix"])
    }

    /// A collection's subscript can never resolve to a project member, so recording it would only
    /// lower the call graph's `coverage`.
    @Test func dropsSubscriptAccessOnBuiltInReceiver() {
        let sites = callSites(in: """
        class Worker {
            var items: [Int] = []
            var lookup: [String: Int] = [:]
            var list: Array<Int> = []
            func run() {
                _ = items[0]
                _ = lookup["a"]
                _ = list[0]
                _ = String()[0]
            }
        }
        """, method: "run")
        #expect(sites.allSatisfy { $0.methodName != "subscript" })
    }
}
