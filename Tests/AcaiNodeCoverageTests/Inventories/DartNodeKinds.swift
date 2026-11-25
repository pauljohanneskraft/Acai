/// What `DartExtractor` does with each node kind the Dart corpus produces.
struct DartNodeKinds {

    var inventory: NodeKindInventory {
        NodeKindInventory(extracted: extracted, ignored: ignored, notDeclarations: notDeclarations)
    }

    private var extracted: [String: ExtractedKind] {
        types.merging(members) { first, _ in first }
    }

    private var types: [String: ExtractedKind] {
        [
            "class_definition": .init(name: NamePath(.field("name"))),
            "enum_declaration": .init(name: NamePath(.field("name"))),
            "mixin_declaration": .init(name: NamePath(.first(["identifier"]))),
            "extension_type_declaration": .init(name: NamePath(.field("name"))),
            "type_alias": .init(name: NamePath(.first(["type_identifier"]))),
            // An unnamed `extension on Foo { … }` has no name to look up.
            "extension_declaration": .init(name: NamePath(.field("name")), requiredFields: ["name"])
        ]
    }

    private var members: [String: ExtractedKind] {
        [
            "enum_constant": .init(name: NamePath(.field("name"))),
            "function_signature": .init(name: NamePath(.field("name"))),
            "getter_signature": .init(name: NamePath(.field("name"))),
            "setter_signature": .init(name: NamePath(.field("name"))),
            "constructor_signature": .init(name: NamePath(.last(["identifier"]))),
            "constant_constructor_signature": .init(name: NamePath(.last(["identifier", "qualified"]))),
            "factory_constructor_signature": .init(
                name: NamePath(.last(["identifier"])),
                knownIssue: "the grammar wraps it in a `method_signature`, and "
                    + "`DartMemberExtractor.resolveMethodSignatureChild` dispatches every sibling "
                    + "signature kind but this one, so a factory constructor is dropped"
            ),
            "operator_signature": .init(name: NamePath(.first(["binary_operator", "minus_operator"]))),
            "initialized_identifier": .init(name: NamePath(.first(["identifier"]))),
            "static_final_declaration": .init(name: NamePath(.first(["identifier"])))
        ]
    }

    private var ignored: [String: String] {
        [
            "library_import": "Module attribution works from file paths, so imports are read for nothing.",
            "import_or_export": "Module attribution works from file paths, so imports are read for nothing.",
            "import_specification": "Part of an import directive, which is read for nothing.",
            "part_directive": "Names a companion file; it declares nothing of its own.",
            "configurable_uri": "The target of an import directive, which is read for nothing.",
            "uri": "The target of an import or part directive, which is read for nothing.",
            "dotted_identifier_list": "An imported library's path, read for nothing.",
            "library_name": "Sets the artifact's namespace; it declares no type of its own.",
            "declaration": "Wraps the class-body member it declares, which is classified on its own.",
            "method_signature": "Wraps the signature that carries the name, which is classified on its own.",
            "initialized_identifier_list": "Holds the `initialized_identifier`s that carry the names.",
            "static_final_declaration_list": "Holds the `static_final_declaration`s that carry the names.",
            "local_variable_declaration": "A local is not a member; its writes and calls are read instead.",
            "initialized_variable_definition": "A local binding is not a member; its calls are read instead.",
            "initializers": "A constructor's initializer list writes existing fields rather than "
                + "declaring any.",
            "initializer_list_entry": "Writes a field the type already declares.",
            "field_initializer": "Writes a field the type already declares.",
            "redirection": "Forwards to another constructor, which is classified on its own.",
            "representation_declaration": "An extension type's representation field is part of its "
                + "declaration, and the extractor records only the type.",
            "formal_parameter": "A parameter belongs to its member's signature, not to the type's members.",
            "formal_parameter_list": "Holds the parameters, which belong to their member's signature.",
            "optional_formal_parameters": "Optional parameters belong to their member's signature.",
            "parameter_type_list": "A function type's parameters belong to its signature.",
            "normal_parameter_type": "A function type's parameter belongs to its signature.",
            "typed_identifier": "A function type's named parameter belongs to its signature.",
            "constructor_param": "A `this.x` constructor parameter writes a field the type already "
                + "declares.",
            "type_parameter": "A generic parameter belongs to its declaration's signature.",
            "type_bound": "A generic parameter's bound belongs to its declaration's signature.",
            "catch_parameters": "A caught error names a local, not a member."
        ]
    }

    private var notDeclarations: Set<String> {
        expressions.union(statements).union(tokens)
    }

    private var expressions: Set<String> {
        [
            "additive_expression", "argument", "argument_part", "arguments", "assignable_expression",
            "assignment_expression", "await_expression", "conditional_assignable_selector",
            "constant_pattern", "equality_expression", "index_selector", "list_literal",
            "logical_and_expression", "multiplicative_expression", "parenthesized_expression",
            "postfix_expression", "relational_expression", "selector", "set_or_map_literal",
            "template_substitution", "type_test_expression", "unary_expression",
            "unconditional_assignable_selector"
        ]
    }

    private var statements: Set<String> {
        [
            "block", "break_statement", "catch_clause", "class_body", "do_statement", "enum_body",
            "expression_statement", "extension_body", "for_element", "for_loop_parts", "for_statement",
            "function_body", "if_statement", "program", "return_statement", "switch_block",
            "switch_statement", "switch_statement_case", "switch_statement_default", "try_statement",
            "while_statement", "yield_statement"
        ]
    }

    private var tokens: Set<String> {
        [
            "abstract", "additive_operator", "annotation", "binary_operator", "break_builtin",
            "case_builtin", "const_builtin", "decimal_floating_point_literal", "decimal_integer_literal",
            "documentation_comment", "equality_operator", "final_builtin", "function_type", "identifier",
            "identifier_dollar_escaped", "increment_operator", "inferred_type", "interface", "interfaces",
            "is_operator", "logical_and_operator", "minus_operator", "mixin", "mixins",
            "multiplicative_operator", "nullable_type", "postfix_operator", "prefix_operator", "qualified",
            "relational_operator", "sealed", "string_literal", "super", "superclass", "this",
            "type_arguments", "type_identifier", "type_parameters", "type_test", "void_type"
        ]
    }
}
