import XCTest
@testable import UMLCore
@testable import UMLCSharp
import UMLTreeSitter

final class CSharpParserTests: XCTestCase {
    func testParser() {
        let parser = CSharpCodeParser()
        let source = """
        namespace MediaLibrary;

        public class MediaItem : IPlayable {
            private readonly string _title;
            public string Title => _title;
            public MediaItem(string title) { _title = title; }
            public virtual void Play() {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "test.cs")
        XCTAssertEqual(artifact.declarations.count, 2) // maybe more depending on IPlayable resolution
        print(artifact)
    }
}
