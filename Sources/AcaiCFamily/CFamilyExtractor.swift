import AcaiCore
import AcaiTreeSitter

/// Walks a tree-sitter C or C++ AST and builds its `CodeArtifact`, sequencing collaborators that
/// each own one concern. Every collaborator is built once, in `init`.
///
/// C and C++ share one extractor because tree-sitter-cpp reuses tree-sitter-c's node types
/// (`struct_specifier`, `enum_specifier`, `function_definition`, `field_declaration`, …). The
/// `dialect` only decides which `SourceLanguage` the artifact reports; the C++-only node types
/// (`class_specifier`, `namespace_definition`, `template_declaration`, `access_specifier`,
/// `base_class_clause`) never appear in a C tree, so handling them unconditionally is safe.
struct CFamilyExtractor {

    /// C/C++ structural decision-point node types for cyclomatic complexity.
    static let branchNodeKinds: Set<String> = [
        "if_statement", "for_statement", "for_range_loop", "while_statement", "do_statement",
        "case_statement", "catch_clause"
    ]

    let context: SourceFileContext
    let dialect: CFamilyDialect
    let typeReferences: CFamilyTypeReferenceResolver
    let memberExtractor: CFamilyMemberExtractor
    let assignmentSyntax: CFamilyAssignmentSyntax
    let callSites: CallSiteResolver
    let assignments: AssignmentResolver
    let fieldReads: FieldReadResolver

    var declarations = DeclarationBuilder()

    /// Takes the tree so the declared-type, declared-function and enum-constant pre-passes run
    /// before the collaborators that read them.
    init(source: String, fileName: String, dialect: CFamilyDialect, root: Node) {
        let context = SourceFileContext(source: source, fileName: fileName)
        let typeReferences = CFamilyTypeReferenceResolver(context: context)

        let declaredTypeNames = TypeNamePrepass(declarationNodeTypes: [
            "struct_specifier", "union_specifier", "enum_specifier", "class_specifier"
        ]).names(in: root) { $0.child(byFieldName: "name").map { $0.text(in: context) } }

        // Collects the simple name behind every `function_declarator` in the file (free functions,
        // prototypes, and member functions alike).
        var declaredFunctionNames: Set<String> = []
        func collectFunctionNames(_ node: Node) {
            if node.nodeType == "function_declarator" {
                let name = typeReferences.lastComponent(
                    of: typeReferences.parseDeclarator(node.child(byFieldName: "declarator")).name)
                if !name.isEmpty { declaredFunctionNames.insert(name) }
            }
            for index in 0..<node.childCount {
                node.child(at: index).map(collectFunctionNames)
            }
        }
        collectFunctionNames(root)

        // Collects the name of every `enumerator` in the file.
        var declaredEnumConstants: Set<String> = []
        func collectEnumConstants(_ node: Node) {
            if node.nodeType == "enumerator", let nameNode = node.child(byFieldName: "name") {
                declaredEnumConstants.insert(nameNode.text(in: context))
            }
            for index in 0..<node.childCount {
                node.child(at: index).map(collectEnumConstants)
            }
        }
        collectEnumConstants(root)

        self.context = context
        self.dialect = dialect
        self.typeReferences = typeReferences
        let assignmentSyntax = CFamilyAssignmentSyntax(context: context, declaredEnumConstants: declaredEnumConstants)
        let callSites = CallSiteResolver(syntax: CFamilyCallSiteSyntax(
            context: context, typeReferences: typeReferences, declaredFunctionNames: declaredFunctionNames))
        self.assignmentSyntax = assignmentSyntax
        self.callSites = callSites
        memberExtractor = CFamilyMemberExtractor(
            context: context, typeReferences: typeReferences, assignmentSyntax: assignmentSyntax,
            callSites: callSites, declaredTypeNames: declaredTypeNames
        )
        assignments = AssignmentResolver(syntax: assignmentSyntax)
        // Bare identifiers, plus the `field_identifier` of a `this->field`/`obj.field` access, are
        // both identifier-shaped nodes.
        fieldReads = FieldReadResolver(context: context, identifierTypes: ["identifier", "field_identifier"])

        declarations.declaredTypeNames = declaredTypeNames
    }

    // MARK: - Public Entry Point

    mutating func extract(from root: Node) -> CodeArtifact {
        walkSourceFile(root)
        declarations.resolveRelationshipNames()
        return declarations.artifact(language: dialect.sourceLanguage, filePath: context.fileName)
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
                declarations.freestandingFunctions.append(function)
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
            if let decl = extractRecord(node) { declarations.types.append(decl) }
        case "enum_specifier":
            if let decl = extractEnum(node) { declarations.types.append(decl) }
        default:
            break
        }
    }

    /// A top-level `declaration` may define a record/enum (via its `type`), declare global
    /// variables, or declare function prototypes — possibly several at once (`struct Point{…} origin;`).
    private mutating func visitTopLevelDeclaration(_ node: Node) {
        if let typeNode = node.child(byFieldName: "type") {
            switch typeNode.nodeType {
            case "struct_specifier", "union_specifier", "class_specifier":
                if typeNode.child(byFieldName: "body") != nil, let decl = extractRecord(typeNode) {
                    declarations.types.append(decl)
                }
            case "enum_specifier":
                if typeNode.child(byFieldName: "body") != nil, let decl = extractEnum(typeNode) {
                    declarations.types.append(decl)
                }
            default:
                break
            }
        }
        extractTopLevelDeclarators(node)
    }

    // MARK: - Namespaces / templates / linkage

    private mutating func visitNamespace(_ node: Node) {
        let previous = declarations.currentNamespace
        if let nameNode = node.child(byFieldName: "name") {
            let name = nameNode.text(in: context)
            _ = declarations.enter(namespace: previous.map { "\($0).\(name)" } ?? name)
        }
        if let body = node.child(byFieldName: "body") {
            visitChildrenAsTopLevel(body)
        }
        declarations.leave(previous)
    }

    /// A `template_declaration` wraps the entity it parameterises (class/struct, function, or a
    /// plain declaration). Extract the inner entity, attaching the template parameters as generics.
    private mutating func visitTemplate(_ node: Node) {
        let generics = typeReferences.templateParameters(node)
        for child in node.namedChildren() {
            switch child.nodeType {
            case "class_specifier", "struct_specifier", "union_specifier":
                if var decl = extractRecord(child) {
                    decl.genericParameters = generics + decl.genericParameters
                    declarations.types.append(decl)
                }
            case "function_definition":
                if let function = extractFunctionDefinition(child, defaultAccess: .public) {
                    declarations.freestandingFunctions.append(function)
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
}
