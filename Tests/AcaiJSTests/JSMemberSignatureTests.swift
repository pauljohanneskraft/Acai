import Testing
@testable import AcaiJS
@testable import AcaiCore

@Suite("TypeScript member signatures")
struct JSMemberSignatureTests {
    let parser = JSCodeParser(isTypeScript: true)

    /// A method whose *name* is a keyword the signature scan looks for — `get`, `set`, `static`,
    /// `async` — is still an ordinary method: the name field is not a modifier.
    @Test func methodNamedLikeAKeywordIsNotAGetterOrStatic() {
        let source = """
        class Box {
            value: number = 0
            get(): number { return this.value }
            static(): number { return 1 }
        }
        """
        let box = parser.parse(source: source, fileName: "box.ts").types[0]
        let getter = box.members.first { $0.name == "get" }
        #expect(getter?.kind == .method)
        #expect(getter?.isComputed == false)
        let staticallyNamed = box.members.first { $0.name == "static" }
        #expect(staticallyNamed?.modifiers.contains(.static) == false)
    }

    /// A class member with no accessibility modifier is public in TypeScript, so it renders `+` like
    /// the same declaration in Swift or Java — not `~`.
    @Test func unannotatedMemberIsPublic() {
        let source = """
        class Box {
            readonly size: number = 0
            resize(size: number): void {}
            private hidden: number = 0
        }
        """
        let box = parser.parse(source: source, fileName: "box.ts").types[0]
        #expect(box.members.first { $0.name == "size" }?.accessLevel == .public)
        #expect(box.members.first { $0.name == "resize" }?.accessLevel == .public)
        #expect(box.members.first { $0.name == "hidden" }?.accessLevel == .private)
    }
}
