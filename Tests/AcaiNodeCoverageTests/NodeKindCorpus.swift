import Foundation
import AcaiCore
import AcaiLibrary
import AcaiTreeSitter

/// The parser goldens' fixtures, the contract matrix's snippets and this target's own, by `#filePath`.
struct NodeKindCorpus {

    /// One plugin: its contract-snippet stem, a grammar per extension, its parser and its inventory.
    struct Plugin: Sendable, CustomStringConvertible {
        let stem: String
        let grammars: [String: TreeSitterGrammar]
        let parser: any CodeParser
        let inventory: NodeKindInventory

        var description: String { stem }
    }

    struct Source: Sendable, CustomStringConvertible {
        let url: URL
        /// The name handed to the parser, which is what routes an extension to its grammar.
        let fileName: String

        /// Enough of the path to tell `optional-type/java.java` from `Fixtures/Shop.java`.
        var description: String {
            "\(url.deletingLastPathComponent().lastPathComponent)/\(fileName)"
        }
    }

    /// One occurrence of an extracted kind: the name it declares and the lines it may sit on.
    struct Occurrence: Sendable {
        let kind: String
        /// The nearest enclosing kind an `ignoredInside` key is matched on; `nil` at file scope.
        let enclosing: String?
        let name: String
        /// The node's start line through its name's line, since an extractor stamps either.
        let headerLines: ClosedRange<Int>
    }

    struct Facts: Sendable {
        var kinds: Set<String> = []
        var occurrences: [Occurrence] = []
        /// Extracted kinds whose `NamePath` read no name — a wrong path, not a dropped declaration.
        var unreadableNames: Set<String> = []
        var hasParseError = false
    }

    enum Failure: Error, CustomStringConvertible {
        case grammarUnavailable(stem: String, fileExtension: String)
        case unparsable(fileName: String)

        var description: String {
            switch self {
            case .grammarUnavailable(let stem, let fileExtension):
                return "The \(stem) inventory covers '.\(fileExtension)' but the corpus holds no grammar for it."
            case .unparsable(let fileName):
                return "\(fileName) produced no tree, so its node kinds could not be classified."
            }
        }
    }

    let directory: URL

    init(testFile: StaticString = #filePath) {
        directory = URL(fileURLWithPath: "\(testFile)").deletingLastPathComponent()
    }

    var plugins: [Plugin] { NodeKindPlugins().all }

    /// Every corpus file this plugin owns, sorted so a failure names the same file on every machine.
    func sources(for plugin: Plugin) -> [Source] {
        let extensions = Set(plugin.grammars.keys)
        let roots = [
            directory.appendingPathComponent("Fixtures"),
            directory.deletingLastPathComponent()
                .appendingPathComponent("AcaiParserGoldenTests")
                .appendingPathComponent("Fixtures")
        ]
        let contractFeatures = directory.deletingLastPathComponent()
            .appendingPathComponent("AcaiContractTests")
            .appendingPathComponent("Features")
        let fixtures = roots.flatMap { files(in: $0) }
            .filter { extensions.contains($0.pathExtension.lowercased()) }
        let snippets = subdirectories(of: contractFeatures).flatMap { files(in: $0) }
            .filter { extensions.contains($0.pathExtension.lowercased()) }
            .filter { $0.deletingPathExtension().lastPathComponent == plugin.stem }
        return (fixtures + snippets)
            .map { Source(url: $0, fileName: $0.lastPathComponent) }
            .sorted { $0.url.path < $1.url.path }
    }

    func facts(of source: Source, plugin: Plugin) throws -> Facts {
        let fileExtension = source.url.pathExtension.lowercased()
        guard let grammar = plugin.grammars[fileExtension] else {
            throw Failure.grammarUnavailable(stem: plugin.stem, fileExtension: fileExtension)
        }
        let text = try String(contentsOf: source.url, encoding: .utf8)
        guard let parser = grammar.makeParser(), let tree = parser.parse(text), let root = tree.rootNode else {
            throw Failure.unparsable(fileName: source.fileName)
        }
        let context = SourceFileContext(source: text, fileName: source.fileName)
        return NodeKindWalk(inventory: plugin.inventory, context: context).facts(in: root)
    }

    func declarations(of source: Source, plugin: Plugin) throws -> DeclarationIndex {
        let text = try String(contentsOf: source.url, encoding: .utf8)
        return DeclarationIndex(artifact: plugin.parser.parse(source: text, fileName: source.fileName))
    }

    private func files(in directory: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey])) ?? []
        return contents.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
    }

    private func subdirectories(of directory: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return contents.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }
}
