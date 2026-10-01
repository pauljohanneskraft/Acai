import Foundation
import Testing
@testable import AcaiJS

/// `tsconfig.json` is JSONC, and the file `tsc --init` writes is comments end to end. Reducing it to
/// strict JSON has to leave the data alone — including the `//` and `,}` that appear inside strings.
@Suite("JSON with comments", .timeLimit(.minutes(1)))
struct JSONWithCommentsTests {

    @Test func lineAndBlockCommentsAreDropped() throws {
        let document = JSONWithComments("""
        {
          // The base this extends.
          "extends": "./base.json", /* inline */
          /* A block
             over two lines. */
          "include": ["src"]
        }
        """)
        let object = try #require(document.object)
        #expect(object["extends"] as? String == "./base.json")
        #expect(object["include"] as? [String] == ["src"])
    }

    @Test func trailingCommasAreDropped() throws {
        let object = try #require(JSONWithComments("""
        {
          "include": [
            "src",
            "lib",
          ],
          "compilerOptions": { "rootDir": "src", },
        }
        """).object)
        #expect(object["include"] as? [String] == ["src", "lib"])
        #expect((object["compilerOptions"] as? [String: Any])?["rootDir"] as? String == "src")
    }

    /// A comment marker inside a string is data, not a comment — the usual way a naive stripper
    /// corrupts a path.
    @Test func commentMarkersInsideStringsSurvive() throws {
        let object = try #require(JSONWithComments("""
        {"include": ["src/**/*", "a//b", "c/*d*/e"], "extends": "./x.json"}
        """).object)
        #expect(object["include"] as? [String] == ["src/**/*", "a//b", "c/*d*/e"])
        #expect(object["extends"] as? String == "./x.json")
    }

    @Test func anEscapedQuoteDoesNotEndTheString() throws {
        let object = try #require(JSONWithComments(#"{"name": "say \"//\"", "include": ["src"]}"#).object)
        #expect(object["name"] as? String == #"say "//""#)
        #expect(object["include"] as? [String] == ["src"])
    }

    /// A comma that belongs between two members is not a trailing one.
    @Test func separatingCommasAreKept() throws {
        let object = try #require(JSONWithComments(#"{"a": [1, 2], "b": {"c": 3}}"#).object)
        #expect(object["a"] as? [Int] == [1, 2])
        #expect((object["b"] as? [String: Any])?["c"] as? Int == 3)
    }

    @Test func somethingThatIsNotAnObjectIsNotRead() {
        #expect(JSONWithComments("[1, 2]").object == nil)
        #expect(JSONWithComments("{ not json at all").object == nil)
        #expect(JSONWithComments("<<<<<<< HEAD\n{}\n=======\n{}\n>>>>>>> other").object == nil)
    }
}
