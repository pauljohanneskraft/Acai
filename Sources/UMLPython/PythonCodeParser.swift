import UMLCore
import UMLTreeSitter
import TreeSitterPython

/// Parses Python source into a `CodeArtifact` on top of the shared `UMLTreeSitter` query/adapter
/// architecture (see `TREESITTER_CODEPARSER_DESIGN.md`).
///
/// Python has no access keywords, no field declarations the way statically-typed languages do
/// (instance attributes appear as `self.x = …` inside methods), and its member "kind" (property vs.
/// method vs. initializer) is driven by decorators and the `__init__` name, not a keyword — none of
/// that is expressible as a query-time keyword lookup, so `PythonCodeParser.parse` runs a
/// post-processing pass (`PythonPostProcessing`) over the structurally-assembled `CodeArtifact` to
/// apply it, the same way the JS plugin's textual `.prototype.` pattern lives outside the
/// query/adapter split.
public struct PythonCodeParser: CodeParser {
    public let language: CodeArtifact.SourceLanguage = .python
    public let fileExtensions: [String] = ["py"]

    private let plugin: TreeSitterLanguagePlugin

    public init() {
        plugin = TreeSitterLanguagePlugin(
            sourceLanguage: .python,
            grammar: Language(language: tree_sitter_python()),
            structuralQuery: try! StructuralQuery(
                language: Language(language: tree_sitter_python()), source: Self.querySource),
            vocabulary: TypeStructureVocabulary(
                kindKeywords: [:],
                modifierKeywords: [:],
                accessKeywords: [:],
                defaultAccessLevel: .public),
            typeReference: PythonTypeReference().resolver,
            literals: LiteralVocabulary(
                boolean: ["true", "false"],
                numeric: ["integer", "float"],
                string: ["string", "concatenated_string"],
                nilLiteral: ["none"]),
            expressionGrammar: PythonExpressionGrammar(),
            topLevelCallNodePredicate: { $0.nodeType == "expression_statement" || $0.nodeType == "if_statement" }
        )
    }

    public func parse(source: String, fileName: String) -> CodeArtifact {
        let artifact = TreeSitterSourceFileExtractor(plugin: plugin).extract(source: source, fileName: fileName)
        return PythonPostProcessing().apply(to: artifact)
    }

    private static let querySource = """
    (class_definition
      name: (identifier) @type.name
      superclasses: (argument_list (identifier) @type.supertype)?
      type_parameters: (type_parameter (type (identifier) @type.generic.param))?
    ) @type

    (decorated_definition
      (decorator)+ @type.annotation
      definition: (class_definition
        name: (identifier) @type.name
        superclasses: (argument_list (identifier) @type.supertype)?
        type_parameters: (type_parameter (type (identifier) @type.generic.param))?
      ) @type
    )

    (function_definition
      name: (identifier) @member.name
      parameters: (parameters
        (identifier)* @member.param @member.param.name
        (typed_parameter (identifier) @member.param.name type: (type) @member.param.type)* @member.param
        (default_parameter name: (identifier) @member.param.name value: (_) @member.param.default)* @member.param
        (typed_default_parameter
          name: (identifier) @member.param.name type: (type) @member.param.type
          value: (_) @member.param.default)* @member.param
        (list_splat_pattern (identifier) @member.param.name)* @member.param @member.param.variadic
        (dictionary_splat_pattern (identifier) @member.param.name)* @member.param @member.param.variadic
      )
      return_type: (type)? @member.type
      body: (block) @member.body
    ) @member

    (decorated_definition
      (decorator)+ @member.annotation
      definition: (function_definition
        name: (identifier) @member.name
        parameters: (parameters
          [
            (identifier) @member.param @member.param.name
            (typed_parameter (identifier) @member.param.name type: (type) @member.param.type) @member.param
            (default_parameter name: (identifier) @member.param.name value: (_) @member.param.default) @member.param
            (typed_default_parameter
              name: (identifier) @member.param.name type: (type) @member.param.type
              value: (_) @member.param.default) @member.param
            (list_splat_pattern (identifier) @member.param.name) @member.param @member.param.variadic
            (dictionary_splat_pattern (identifier) @member.param.name) @member.param @member.param.variadic
          ]*
        )
        return_type: (type)? @member.type
        body: (block) @member.body
      ) @member
    )

    (class_definition
      body: (block
        (expression_statement
          (assignment
            left: (identifier) @member.name
            type: (type)? @member.type
            right: (_)? @member.initialValue
          ) @member
          (#set! member.kind "property")
        )
      )
    )

    (assignment
      left: (attribute
        object: (identifier) @_selfObject
        attribute: (identifier) @member.name)
      type: (type)? @member.type
      right: (_)? @member.initialValue
      (#any-of? @_selfObject "self" "cls")
      (#set! member.kind "property")
    ) @member

    (module
      (expression_statement
        (assignment
          left: (identifier) @member.name
          type: (type)? @member.type
          right: (_)? @member.initialValue
        ) @member
        (#set! member.kind "property")
      )
    )
    """
}
