/// What `JSExtractor` does with each node kind the JavaScript corpus produces, with
/// `isTypeScript` false — interfaces, type aliases and enums are skipped, so the TSX grammar's
/// TypeScript-only kinds never reach this corpus.
struct JavaScriptNodeKinds {

    var inventory: NodeKindInventory {
        NodeKindInventory(extracted: extracted, ignored: ignored, notDeclarations: notDeclarations)
    }

    private var extracted: [String: ExtractedKind] {
        [
            "class_declaration": .init(name: NamePath(.field("name"))),
            "method_definition": .init(name: NamePath(.field("name"))),
            "public_field_definition": .init(name: NamePath(.field("name"))),
            "function_declaration": .init(name: NamePath(.field("name"))),
            "variable_declarator": .init(
                name: NamePath(.field("name")),
                ignoredInside: [
                    "function_declaration": "A local binding is not a declaration; its calls are read instead.",
                    "method_definition": "A local binding is not a declaration; its calls are read instead."
                ]
            )
        ]
    }

    private var ignored: [String: String] {
        [
            "import_statement": "Module attribution works from file paths, so imports are read for nothing.",
            "import_clause": "Part of an `import_statement`, which is read for nothing.",
            "import_specifier": "Part of an `import_statement`, which is read for nothing.",
            "named_imports": "Part of an `import_statement`, which is read for nothing.",
            "export_statement": "Wraps the declaration it exports, which is classified on its own.",
            "lexical_declaration": "Holds the `variable_declarator`s that carry the names.",
            "function_expression": "An expression; the binding that holds it carries the name.",
            "required_parameter": "A parameter belongs to its member's signature. JavaScript has no "
                + "parameter properties, so none is ever promoted to a member.",
            "pair": "An object literal's entry is a value, not a declared member.",
            "shorthand_property_identifier_pattern": "A destructuring binding names a local."
        ]
    }

    private var notDeclarations: Set<String> {
        [
            "arguments", "array_pattern", "arrow_function", "assignment_expression",
            "augmented_assignment_expression", "binary_expression", "call_expression", "class_body",
            "class_heritage", "comment", "else_clause", "expression_statement", "extends_clause", "false",
            "for_statement", "formal_parameters", "identifier", "if_statement", "jsx_attribute",
            "jsx_closing_element", "jsx_element", "jsx_expression", "jsx_opening_element",
            "jsx_self_closing_element", "jsx_text", "member_expression", "new_expression", "number", "object",
            "object_pattern", "parenthesized_expression", "private_property_identifier", "program",
            "property_identifier", "return_statement", "spread_element", "statement_block", "string",
            "string_fragment", "super", "ternary_expression", "this", "true", "type_identifier",
            "unary_expression", "update_expression"
        ]
    }
}
