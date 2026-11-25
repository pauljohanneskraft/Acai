/// What `CFamilyExtractor` does, in its C dialect, with each node kind the C corpus produces.
struct CNodeKinds {

    var inventory: NodeKindInventory {
        NodeKindInventory(extracted: extracted, ignored: ignored, notDeclarations: notDeclarations)
    }

    private var extracted: [String: ExtractedKind] {
        [
            // A specifier with a name but no body is a type reference (`struct Logger audit;`), and one
            // with a body but no name is the anonymous half of a typedef, named by its `type_definition`.
            "struct_specifier": .init(
                name: NamePath(.field("name")),
                requiredChildren: ["type_identifier", "field_declaration_list"]
            ),
            "enum_specifier": .init(
                name: NamePath(.field("name")),
                requiredChildren: ["type_identifier", "enumerator_list"]
            ),
            "type_definition": .init(name: NamePath(.chain("declarator"))),
            "enumerator": .init(name: NamePath(.field("name"))),
            "field_declaration": .init(name: NamePath(.chain("declarator")), requiredFields: ["declarator"]),
            "function_definition": .init(name: NamePath(.chain("declarator")))
        ]
    }

    private var ignored: [String: String] {
        [
            "preproc_include": "Module attribution works from file paths, so includes are read for nothing.",
            "system_lib_string": "The header named by an `#include`, which is read for nothing.",
            "declaration": "At file scope a prototype or a global, inside a body a local. The C corpus "
                + "reaches only the body form, so no occurrence can be held to the file-scope rule.",
            "init_declarator": "A declarator's name site, reached through the `declaration` that holds it.",
            "parameter_declaration": "A parameter belongs to its function's signature.",
            "array_declarator": "Part of a declarator chain, reached through the declaration it names.",
            "pointer_declarator": "Part of a declarator chain, reached through the declaration it names.",
            "function_declarator": "Part of a declarator chain, reached through the definition it names."
        ]
    }

    private var notDeclarations: Set<String> {
        [
            "argument_list", "assignment_expression", "binary_expression", "call_expression", "comment",
            "compound_statement", "else_clause", "enumerator_list", "expression_statement",
            "field_declaration_list", "field_expression", "field_identifier", "for_statement", "identifier",
            "if_statement", "number_literal", "parameter_list", "parenthesized_expression", "primitive_type",
            "return_statement", "sizeof_expression", "storage_class_specifier", "translation_unit",
            "type_descriptor", "type_identifier", "type_qualifier", "update_expression"
        ]
    }
}
