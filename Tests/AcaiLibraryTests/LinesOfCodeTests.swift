import Testing
import AcaiCore
@testable import AcaiLibrary

/// Pins the physical lines-of-code count for one small fixture per bundled language (#330). A metric
/// computed over a language whose parser doesn't supply declaration extents is silently wrong, so
/// every language gets its own pinned number rather than one representative language standing in.
///
/// Each fixture opens with a line outside the type and closes with one after it, so a parser that
/// reported the whole file instead of the declaration's extent would fail rather than coincide.
@Suite("Lines of code per language")
struct LinesOfCodeTests {

    struct Fixture: Sendable, CustomStringConvertible {
        let name: String
        let parser: any CodeParser
        let fileName: String
        let source: String
        /// The type the count is pinned for, and the lines its declaration spans.
        let typeName: String
        let linesOfCode: Int

        var description: String { name }
    }

    static let fixtures: [Fixture] = [
        Fixture(name: "Swift", parser: SwiftCodeParser(), fileName: "Box.swift", source: """
        import Foundation
        struct Box {
            var width: Int
            var height: Int
            func area() -> Int { width * height }
        }
        let unit = Box(width: 1, height: 1)
        """, typeName: "Box", linesOfCode: 5),
        Fixture(name: "Java", parser: JavaCodeParser(), fileName: "Box.java", source: """
        package com.example;
        class Box {
            int width;
            int height;
            int area() { return width * height; }
        }
        """, typeName: "com.example.Box", linesOfCode: 5),
        Fixture(name: "Kotlin", parser: KotlinCodeParser(), fileName: "Box.kt", source: """
        package com.example
        class Box {
            var width: Int = 0
            var height: Int = 0
            fun area(): Int = width * height
        }
        """, typeName: "com.example.Box", linesOfCode: 5),
        Fixture(name: "TypeScript", parser: JSCodeParser(), fileName: "box.ts", source: """
        // header
        class Box {
            width: number = 0
            height: number = 0
            area(): number { return this.width * this.height }
        }
        export const unit = new Box()
        """, typeName: "Box", linesOfCode: 5),
        Fixture(name: "JavaScript", parser: JSCodeParser(isTypeScript: false), fileName: "box.js", source: """
        // header
        class Box {
            constructor() { this.width = 0 }
            area() { return this.width }
        }
        const unit = new Box()
        """, typeName: "Box", linesOfCode: 4),
        Fixture(name: "Python", parser: PythonCodeParser(), fileName: "box.py", source: """
        # header
        class Box:
            def __init__(self):
                self.width = 0
            def area(self):
                return self.width
        unit = Box()
        """, typeName: "Box", linesOfCode: 5),
        Fixture(name: "Dart", parser: DartCodeParser(), fileName: "box.dart", source: """
        // header
        class Box {
          int width = 0;
          int height = 0;
          int area() => width * height;
        }
        final unit = Box();
        """, typeName: "Box", linesOfCode: 5),
        Fixture(name: "C", parser: CCodeParser(), fileName: "box.c", source: """
        /* header */
        struct Box {
            int width;
            int height;
        };
        """, typeName: "Box", linesOfCode: 4),
        Fixture(name: "C++", parser: CppCodeParser(), fileName: "box.cpp", source: """
        // header
        class Box {
        public:
            int width;
            int area() const { return width; }
        };
        """, typeName: "Box", linesOfCode: 5)
    ]

    @Test("every language reports its declaration's physical lines", arguments: fixtures)
    func reportsLinesOfCode(fixture: Fixture) throws {
        let metrics = fixture.parser
            .parse(source: fixture.source, fileName: fixture.fileName)
            .enriched(configuration: fixture.parser.configuration)
            .computeMetrics()
        let measured = try #require(
            metrics.types.first { $0.name == fixture.typeName },
            Comment(rawValue: "\(fixture.name): no metric for \(fixture.typeName)")
        )
        #expect(measured.linesOfCode == fixture.linesOfCode, Comment(rawValue: fixture.name))
    }

    /// The count is a declaration extent, not a file line count: the fixtures' leading and trailing
    /// lines are outside every type, so no type may claim the whole file.
    @Test("no language counts the whole file for a type", arguments: fixtures)
    func countsLessThanTheWholeFile(fixture: Fixture) {
        let fileLines = fixture.source.split(separator: "\n", omittingEmptySubsequences: false).count
        let metrics = fixture.parser
            .parse(source: fixture.source, fileName: fixture.fileName)
            .enriched(configuration: fixture.parser.configuration)
            .computeMetrics()
        for measured in metrics.types {
            let subject = Comment(rawValue: "\(fixture.name): \(measured.name)")
            #expect(measured.linesOfCode < fileLines, subject)
            #expect(measured.linesOfCode > 0, subject)
        }
    }
}
