/// What `JSExtractor` does with each node kind the TypeScript corpus produces, with
/// `isTypeScript` true — type annotations, interfaces, type aliases and enums all parsed.
struct TypeScriptNodeKinds {

    var inventory: NodeKindInventory {
        NodeKindInventory(extracted: extracted, ignored: ignored, notDeclarations: notDeclarations)
    }

    private var extracted: [String: ExtractedKind] {
        [
            "class_declaration": .init(name: NamePath(.field("name"))),
            "abstract_class_declaration": .init(name: NamePath(.field("name"))),
            "interface_declaration": .init(name: NamePath(.field("name"))),
            "type_alias_declaration": .init(name: NamePath(.field("name"))),
            "enum_declaration": .init(name: NamePath(.field("name"))),
            "method_definition": .init(name: NamePath(.field("name"))),
            "method_signature": .init(name: NamePath(.field("name"))),
            "abstract_method_signature": .init(name: NamePath(.field("name"))),
            "public_field_definition": .init(name: NamePath(.field("name"))),
            "function_declaration": .init(name: NamePath(.field("name"))),
            "enum_assignment": .init(
                name: NamePath(.field("name")),
                knownIssue: "JSExtractor builds the `EnumCase` with no `location`, so nothing ties the "
                    + "case back to its line"
            ),
            "property_signature": .init(
                name: NamePath(.field("name")),
                knownIssueInside: [
                    "type_alias_declaration": "A type alias keeps only its name — the object type's "
                        + "properties are never extracted"
                ]
            ),
            "required_parameter": .init(
                name: NamePath(.field("pattern")),
                requiredChild: "accessibility_modifier",
                knownIssue: "a constructor parameter property becomes a member with no `location`, so "
                    + "nothing ties the declaration back to its line"
            ),
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
            "type_parameter": "A generic parameter belongs to its declaration's signature.",
            "pair": "An object literal's entry is a value, not a declared member.",
            "shorthand_property_identifier_pattern": "A destructuring binding names a local."
        ]
    }

    private var notDeclarations: Set<String> {
        [
            "accessibility_modifier", "arguments", "array", "array_pattern", "array_type", "arrow_function",
            "assignment_expression", "augmented_assignment_expression", "binary_expression", "call_expression",
            "class_body", "class_heritage", "comment", "decorator", "else_clause", "enum_body",
            "expression_statement", "extends_clause", "false", "for_statement", "formal_parameters",
            "function_type", "generic_type", "identifier", "if_statement", "implements_clause",
            "interface_body", "jsx_attribute", "jsx_closing_element", "jsx_element", "jsx_expression",
            "jsx_opening_element", "jsx_self_closing_element", "jsx_text", "member_expression",
            "new_expression", "number", "object", "object_pattern", "object_type", "override_modifier",
            "parenthesized_expression", "predefined_type", "program", "property_identifier", "return_statement",
            "spread_element", "statement_block", "string", "string_fragment", "super", "template_string",
            "template_substitution", "ternary_expression", "this", "true", "type_annotation", "type_arguments",
            "type_identifier", "type_parameters", "unary_expression", "update_expression"
        ]
    }
}
