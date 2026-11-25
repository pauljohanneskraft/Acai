/// What `CFamilyExtractor` does, in its C++ dialect, with each node kind the C++ corpus produces.
struct CppNodeKinds {

    var inventory: NodeKindInventory {
        NodeKindInventory(extracted: extracted, ignored: ignored, notDeclarations: notDeclarations)
    }

    private var extracted: [String: ExtractedKind] {
        [
            // A specifier with a name but no body is a type reference; one with a body but no name is
            // an anonymous aggregate, which carries no name to look up.
            "class_specifier": .init(
                name: NamePath(.field("name")),
                requiredChildren: ["type_identifier", "field_declaration_list"]
            ),
            "struct_specifier": .init(
                name: NamePath(.field("name")),
                requiredChildren: ["type_identifier", "field_declaration_list"]
            ),
            "enum_specifier": .init(
                name: NamePath(.field("name")),
                requiredChildren: ["type_identifier", "enumerator_list"]
            ),
            "enumerator": .init(name: NamePath(.field("name"))),
            "field_declaration": .init(name: NamePath(.chain("declarator")), requiredFields: ["declarator"]),
            "function_definition": .init(name: NamePath(.chain("declarator"))),
            "declaration": .init(
                name: NamePath(.chain("declarator")),
                requiredFields: ["declarator"],
                ignoredInside: [
                    "function_definition": "A local is not a member; its writes and calls are read instead."
                ]
            ),
            "alias_declaration": .init(
                name: NamePath(.field("name")),
                knownIssue: "#517"
            )
        ]
    }

    private var ignored: [String: String] {
        [
            "preproc_include": "Module attribution works from file paths, so includes are read for nothing.",
            "system_lib_string": "The header named by an `#include`, which is read for nothing.",
            "namespace_definition": "A namespace qualifies the names declared inside it; it declares no "
                + "type of its own.",
            "template_declaration": "Wraps the declaration it parameterizes, which is classified on its own.",
            "type_parameter_declaration": "A generic parameter belongs to its declaration's signature.",
            "parameter_declaration": "A parameter belongs to its function's signature.",
            "optional_parameter_declaration": "A defaulted parameter belongs to its function's signature.",
            "init_declarator": "A declarator's name site, reached through the `declaration` that holds it.",
            "function_declarator": "Part of a declarator chain, reached through the declaration it names.",
            "reference_declarator": "Part of a declarator chain, reached through the declaration it names."
        ]
    }

    private var notDeclarations: Set<String> {
        [
            "access_specifier", "argument_list", "assignment_expression", "base_class_clause",
            "binary_expression", "call_expression", "comment", "compound_statement", "condition_clause",
            "declaration_list", "default_method_clause", "destructor_name", "else_clause", "enumerator_list",
            "explicit_function_specifier", "expression_statement", "field_declaration_list", "field_expression",
            "field_identifier", "for_statement", "identifier", "if_statement", "namespace_identifier",
            "number_literal", "parameter_list", "primitive_type", "qualified_identifier", "return_statement",
            "storage_class_specifier", "string_content", "string_literal", "template_argument_list",
            "template_parameter_list", "template_type", "translation_unit", "type_descriptor", "type_identifier",
            "type_qualifier", "update_expression", "virtual_specifier"
        ]
    }
}
