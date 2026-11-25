/// What `PythonExtractor` does with each node kind the Python corpus produces.
struct PythonNodeKinds {

    var inventory: NodeKindInventory {
        NodeKindInventory(
            extracted: extracted, ignored: ignored, notDeclarations: notDeclarations,
            scopeKinds: ["if_statement"]
        )
    }

    private var extracted: [String: ExtractedKind] {
        [
            "class_definition": .init(name: NamePath(.field("name"))),
            "function_definition": .init(name: NamePath(.field("name"))),
            // At module scope a global, in a class body an attribute or an enum case.
            "assignment": .init(
                name: NamePath(.field("left")),
                ignoredInside: [
                    "function_definition": "Inside a body only `self.x = …` declares an attribute and a "
                        + "plain binding declares a local, and the grammar spells both `assignment`, so "
                        + "the two cannot be told apart here.",
                    "if_statement": "A module-level `if` contributes only its call sites, so a binding "
                        + "made under one is not recorded as a global."
                ]
            )
        ]
    }

    private var ignored: [String: String] {
        [
            "import_statement": "Module attribution works from file paths, so imports are read for nothing.",
            "import_from_statement": "Module attribution works from file paths, so imports are read "
                + "for nothing.",
            "dotted_name": "An imported module's path, read for nothing.",
            "decorated_definition": "Wraps the declaration it decorates, which is classified on its own.",
            "parameters": "Holds the parameters, which belong to their member's signature.",
            "typed_parameter": "A parameter belongs to its member's signature, not to the type's members.",
            "typed_default_parameter": "A parameter belongs to its member's signature.",
            "list_splat_pattern": "A `*args` parameter belongs to its member's signature.",
            "dictionary_splat_pattern": "A `**kwargs` parameter belongs to its member's signature.",
            "keyword_separator": "The bare `*` marking keyword-only parameters declares nothing.",
            "type_parameter": "A generic parameter belongs to its declaration's signature.",
            "augmented_assignment": "Writes an existing binding rather than declaring one.",
            "pair": "A dictionary entry is a value, not a declared member."
        ]
    }

    private var notDeclarations: Set<String> {
        [
            "argument_list", "attribute", "binary_operator", "block", "boolean_operator", "call",
            "comparison_operator", "conditional_expression", "decorator", "dictionary", "elif_clause",
            "ellipsis", "else_clause", "except_clause", "expression_statement", "false", "float",
            "for_in_clause", "for_statement", "generic_type", "identifier", "if_clause", "if_statement",
            "integer", "interpolation", "list", "list_comprehension", "module", "none",
            "parenthesized_expression", "pass_statement", "return_statement", "string", "string_content",
            "string_end", "string_start", "subscript", "true", "try_statement", "tuple", "type",
            "unary_operator", "while_statement"
        ]
    }
}
