import Foundation

/// Writes a synthetic source corpus for the performance regression tests. The same seed and shape
/// always produce byte-identical files, so one run's counters are comparable with another's.
public struct SourceCorpusGenerator: Sendable {

    public enum Language: String, Sendable, CaseIterable {
        case swift
        case java

        var fileExtension: String {
            switch self {
            case .swift:
                "swift"
            case .java:
                "java"
            }
        }

        /// Java declares no extensions, so ``SourceCorpusGenerator/Shape/extensionsPerFile`` is
        /// inert for it rather than approximated by some other declaration.
        var hasExtensions: Bool { self == .swift }
    }

    public struct Shape: Sendable {
        public var files: Int
        public var typesPerFile: Int
        public var extensionsPerFile: Int
        /// How many of a file's types nest a type under one shared name, so ids collide across files
        /// the way a real corpus's repeated `Error`/`Configuration` nestings do.
        public var sameNamedNestedTypesPerFile: Int
        /// Parenthesis nesting of the one expression in each generated method.
        public var expressionDepth: Int

        public init(
            files: Int,
            typesPerFile: Int = 8,
            extensionsPerFile: Int = 0,
            sameNamedNestedTypesPerFile: Int = 0,
            expressionDepth: Int = 1
        ) {
            self.files = files
            self.typesPerFile = typesPerFile
            self.extensionsPerFile = extensionsPerFile
            self.sameNamedNestedTypesPerFile = sameNamedNestedTypesPerFile
            self.expressionDepth = expressionDepth
        }
    }

    public let seed: UInt64
    public let language: Language
    public let shape: Shape

    public init(shape: Shape, language: Language = .swift, seed: UInt64 = 0x5eed_c0de) {
        self.shape = shape
        self.language = language
        self.seed = seed
    }

    /// The corpus as `(fileName, text)` pairs, in generation order.
    public func sources() -> [(fileName: String, text: String)] {
        var random = SeededGenerator(seed: seed)
        var result: [(fileName: String, text: String)] = []
        result.reserveCapacity(shape.files)
        for index in 0..<shape.files {
            let names = (0..<shape.typesPerFile).map { "Type\(index)_\($0)" }
            let stem = names.first ?? "Empty\(index)"
            result.append((fileName: "\(stem).\(language.fileExtension)", text: text(names: names, random: &random)))
        }
        return result
    }

    /// Writes the corpus into `directory`, creating it if needed, and returns the files written.
    @discardableResult
    public func write(into directory: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try sources().map { source in
            let url = directory.appendingPathComponent(source.fileName)
            try source.text.write(to: url, atomically: true, encoding: .utf8)
            return url
        }
    }

    // MARK: - Emission

    private func text(names: [String], random: inout SeededGenerator) -> String {
        var lines: [String] = []
        if language == .java {
            lines.append("package generated;")
            lines.append("")
        }
        for (position, name) in names.enumerated() {
            lines.append(contentsOf: typeLines(
                name: name, nestingShared: position < shape.sameNamedNestedTypesPerFile, random: &random
            ))
            lines.append("")
        }
        if language.hasExtensions, !names.isEmpty {
            for index in 0..<shape.extensionsPerFile {
                lines.append(contentsOf: extensionLines(target: names[index % names.count], index: index))
                lines.append("")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func typeLines(name: String, nestingShared: Bool, random: inout SeededGenerator) -> [String] {
        var body: [String] = []
        for index in 0..<random.int(in: 1...3) {
            body.append(
                language == .swift ? "    var value\(index): Int = \(index)" : "    int value\(index) = \(index);"
            )
        }
        for index in 0..<random.int(in: 1...2) {
            body.append(contentsOf: methodLines(index: index))
        }
        if nestingShared {
            body.append(contentsOf: sharedNestedTypeLines())
        }
        return ["\(language == .swift ? "struct" : "class") \(name) {"] + body + ["}"]
    }

    private func methodLines(index: Int) -> [String] {
        let expression = nestedExpression(depth: shape.expressionDepth)
        switch language {
        case .swift:
            return [
                "    func compute\(index)() -> Int {",
                "        let result = \(expression)",
                "        return result",
                "    }"
            ]
        case .java:
            return [
                "    int compute\(index)() {",
                "        int result = \(expression);",
                "        return result;",
                "    }"
            ]
        }
    }

    private func nestedExpression(depth: Int) -> String {
        var expression = "1"
        for _ in 0..<max(depth, 1) {
            expression = "(1 + \(expression))"
        }
        return expression
    }

    private func sharedNestedTypeLines() -> [String] {
        switch language {
        case .swift:
            return ["    struct Shared {", "        var marker: Int = 0", "    }"]
        case .java:
            return ["    class Shared {", "        int marker = 0;", "    }"]
        }
    }

    private func extensionLines(target: String, index: Int) -> [String] {
        ["extension \(target) {", "    func extra\(index)() -> Int { value0 }", "}"]
    }
}
