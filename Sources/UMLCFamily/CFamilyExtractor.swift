import UMLCore
import UMLTreeSitter

/// Walks a tree-sitter C or C++ AST and produces UMLCore model types.
///
/// C and C++ share one extractor because tree-sitter-cpp reuses tree-sitter-c's node types
/// (`struct_specifier`, `enum_specifier`, `function_definition`, `field_declaration`, …). The
/// `dialect` only decides which `SourceLanguage` the artifact reports; the C++-only node types
/// (`class_specifier`, `namespace_definition`, `template_declaration`, `access_specifier`,
/// `base_class_clause`) never appear in a C tree, so handling them unconditionally is safe.
struct CFamilyExtractor: TreeSitterExtracting {

    /// C/C++ structural decision-point node types for cyclomatic complexity.
    static let branchNodeKinds: Set<String> = [
        "if_statement", "for_statement", "for_range_loop", "while_statement", "do_statement",
        "case_statement", "catch_clause"
    ]

    let context: SourceFileContext
    let dialect: CFamilyDialect

    var types: [TypeDeclaration] = []
    var relationships: [Relationship] = []
    var freestandingFunctions: [Member] = []
    var globalVariables: [Member] = []
    var currentNamespace: String?
    var declaredTypeNames: Set<String> = []
    /// Simple names of every function/method declared in the file, collected in a pre-pass so an
    /// unqualified call `foo()` can be resolved to a free function / same-type method (and only then).
    var declaredFunctionNames: Set<String> = []
    /// Names of every enum constant declared in the file, collected in a pre-pass so a bare
    /// identifier on the right of an assignment (C's unscoped `state = DOWNLOADING`) can be
    /// classified as an enumerable `.enumCase` value rather than an opaque expression.
    var declaredEnumConstants: Set<String> = []
    /// `parameterName: typeName` for the free function currently being analysed, so a
    /// `param->field = …` write can be attributed to the parameter's struct type (state-machine
    /// analysis). Empty outside a free-function body.
    var currentReceiverTypes: [String: String] = [:]

    init(source: String, fileName: String, dialect: CFamilyDialect) {
        self.context = SourceFileContext(source: source, fileName: fileName)
        self.dialect = dialect
    }

    mutating func extract(from root: Node) -> CodeArtifact {
        declaredTypeNames = collectDeclaredTypeNames(
            from: root,
            declarationNodeTypes: [
                "struct_specifier", "union_specifier", "enum_specifier", "class_specifier"
            ],
            name: { $0.child(byFieldName: "name").map { self.text($0) } }
        )
        declaredFunctionNames = collectDeclaredFunctionNames(from: root)
        declaredEnumConstants = collectEnumConstantNames(from: root)
        walkSourceFile(root)
        resolveRelationshipNames()
        return CodeArtifact(
            metadata: .init(sourceLanguage: dialect.sourceLanguage, filePaths: [context.fileName]),
            types: types,
            relationships: relationships,
            freestandingFunctions: freestandingFunctions,
            globalVariables: globalVariables
        )
    }

    // MARK: - Top-level traversal

    mutating func walkSourceFile(_ node: Node) {
        for child in node.children() {
            visitTopLevel(child)
        }
    }

    private mutating func visitTopLevel(_ node: Node) {
        switch node.nodeType {
        case "declaration":
            visitTopLevelDeclaration(node)
        case "type_definition":
            extractTypedef(node)
        case "function_definition":
            if let function = extractFunctionDefinition(node, defaultAccess: .public) {
                freestandingFunctions.append(function)
            }
        case "namespace_definition":
            visitNamespace(node)
        case "template_declaration":
            visitTemplate(node)
        case "linkage_specification":
            visitChildrenAsTopLevel(node)
        case "preproc_ifdef", "preproc_if", "preproc_else", "preproc_elif", "preproc_elifdef":
            // Include guards (`#ifndef FOO_H … #endif`) and conditional compilation wrap their
            // guarded declarations as children; descend so those declarations are still seen.
            visitChildrenAsTopLevel(node)
        default:
            appendTopLevelSpecifier(node)
        }
    }

    /// A bare record/enum specifier at file scope (e.g. inside an `extern "C"` block or a namespace).
    private mutating func appendTopLevelSpecifier(_ node: Node) {
        switch node.nodeType {
        case "struct_specifier", "union_specifier", "class_specifier":
            if let decl = extractRecord(node) { types.append(decl) }
        case "enum_specifier":
            if let decl = extractEnum(node) { types.append(decl) }
        default:
            break
        }
    }

    /// A top-level `declaration` may define a record/enum (via its `type`), declare global
    /// variables, or declare function prototypes — possibly several at once
    /// (e.g. `struct Point { … } origin;`).
    private mutating func visitTopLevelDeclaration(_ node: Node) {
        if let typeNode = node.child(byFieldName: "type") {
            switch typeNode.nodeType {
            case "struct_specifier", "union_specifier", "class_specifier":
                if typeNode.child(byFieldName: "body") != nil, let decl = extractRecord(typeNode) {
                    types.append(decl)
                }
            case "enum_specifier":
                if typeNode.child(byFieldName: "body") != nil, let decl = extractEnum(typeNode) {
                    types.append(decl)
                }
            default:
                break
            }
        }
        extractTopLevelDeclarators(node)
    }

    // MARK: - Namespaces / templates / linkage

    private mutating func visitNamespace(_ node: Node) {
        let previous = currentNamespace
        if let nameNode = node.child(byFieldName: "name") {
            let name = text(nameNode)
            currentNamespace = previous.map { "\($0).\(name)" } ?? name
        }
        if let body = node.child(byFieldName: "body") {
            visitChildrenAsTopLevel(body)
        }
        currentNamespace = previous
    }

    /// A `template_declaration` wraps the entity it parameterises (class/struct, function, or a
    /// plain declaration). Extract the inner entity, attaching the template parameters as generics.
    private mutating func visitTemplate(_ node: Node) {
        let generics = templateParameters(node)
        for child in node.namedChildren() {
            switch child.nodeType {
            case "class_specifier", "struct_specifier", "union_specifier":
                if var decl = extractRecord(child) {
                    decl.genericParameters = generics + decl.genericParameters
                    types.append(decl)
                }
            case "function_definition":
                if let function = extractFunctionDefinition(child, defaultAccess: .public) {
                    freestandingFunctions.append(function)
                }
            case "declaration":
                visitTopLevelDeclaration(child)
            default:
                break
            }
        }
    }

    private mutating func visitChildrenAsTopLevel(_ node: Node) {
        for child in node.children() {
            visitTopLevel(child)
        }
    }

    /// Collects the simple name behind every `function_declarator` in the file (free functions,
    /// prototypes, and member functions alike).
    private func collectDeclaredFunctionNames(from root: Node) -> Set<String> {
        var names: Set<String> = []
        func walk(_ node: Node) {
            if node.nodeType == "function_declarator" {
                let name = Self.lastComponent(of: parseDeclarator(node.child(byFieldName: "declarator")).name)
                if !name.isEmpty { names.insert(name) }
            }
            for index in 0..<node.childCount {
                node.child(at: index).map(walk)
            }
        }
        walk(root)
        return names
    }

    /// Collects the name of every `enumerator` in the file (the constants declared by each
    /// `enum`/`enum class`), so an unscoped enum constant assigned to a variable is recognised as
    /// an enumerable value for state-machine analysis.
    private func collectEnumConstantNames(from root: Node) -> Set<String> {
        var names: Set<String> = []
        func walk(_ node: Node) {
            if node.nodeType == "enumerator", let name = node.child(byFieldName: "name").map({ text($0) }) {
                names.insert(name)
            }
            for index in 0..<node.childCount {
                node.child(at: index).map(walk)
            }
        }
        walk(root)
        return names
    }
}
