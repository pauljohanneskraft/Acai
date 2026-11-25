/// What `JavaExtractor` does with each node kind the Java corpus produces.
struct JavaNodeKinds {

    var inventory: NodeKindInventory {
        NodeKindInventory(extracted: extracted, ignored: ignored, notDeclarations: notDeclarations)
    }

    private var extracted: [String: ExtractedKind] {
        [
            "class_declaration": .init(name: NamePath(.field("name"))),
            "interface_declaration": .init(name: NamePath(.field("name"))),
            "enum_declaration": .init(name: NamePath(.field("name"))),
            "record_declaration": .init(name: NamePath(.field("name"))),
            "enum_constant": .init(name: NamePath(.field("name"))),
            "constructor_declaration": .init(name: NamePath(.field("name"))),
            "method_declaration": .init(
                name: NamePath(.field("name")),
                knownIssueInside: ["enum_constant": "#610"]
            ),
            "field_declaration": .init(name: NamePath(.field("declarator"), .field("name")))
        ]
    }

    private var ignored: [String: String] {
        [
            "package_declaration": "Sets the artifact's namespace; it declares no type of its own.",
            "import_declaration": "Module attribution works from file paths, so imports are read for nothing.",
            "local_variable_declaration": "A local is not a member; its writes and calls are read instead.",
            "variable_declarator": "A field's name site, reached through its `field_declaration`; under a "
                + "`local_variable_declaration` it names a local.",
            "formal_parameter": "A parameter belongs to its member's signature, not to the type's members.",
            "type_parameter": "A generic parameter belongs to its declaration's signature."
        ]
    }

    private var notDeclarations: Set<String> {
        [
            "argument_list", "assignment_expression", "binary_expression", "block", "block_comment",
            "boolean_type", "class_body", "constructor_body", "decimal_floating_point_literal",
            "decimal_integer_literal", "enum_body", "enum_body_declarations", "explicit_constructor_invocation",
            "expression_statement", "field_access", "floating_point_type", "for_statement", "formal_parameters",
            "generic_type", "identifier", "if_statement", "integral_type", "interface_body", "line_comment",
            "marker_annotation",
            "method_invocation", "modifiers", "object_creation_expression", "parenthesized_expression", "program",
            "return_statement", "scoped_identifier", "string_fragment", "string_literal", "super",
            "super_interfaces", "superclass", "this", "type_arguments", "type_identifier", "type_list",
            "type_parameters", "update_expression", "void_type"
        ]
    }
}
