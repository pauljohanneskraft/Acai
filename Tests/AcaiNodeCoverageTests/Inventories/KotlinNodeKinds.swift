/// What `KotlinExtractor` does with each node kind the Kotlin corpus produces.
struct KotlinNodeKinds {

    var inventory: NodeKindInventory {
        NodeKindInventory(extracted: extracted, ignored: ignored, notDeclarations: notDeclarations)
    }

    private var extracted: [String: ExtractedKind] {
        [
            "class_declaration": .init(name: NamePath(.kind("type_identifier"))),
            "companion_object": .init(name: NamePath(synthesizedName: "Companion")),
            "enum_entry": .init(name: NamePath(.kind("simple_identifier"))),
            "secondary_constructor": .init(name: NamePath(synthesizedName: "init")),
            "function_declaration": .init(
                name: NamePath(.kind("simple_identifier")),
                ignoredInside: ["function_declaration": "A local function is not a member of the enclosing type."]
            ),
            "property_declaration": .init(
                name: NamePath(.kind("variable_declaration"), .kind("simple_identifier")),
                ignoredInside: [
                    "function_declaration": "A local binding is not a member; its calls are read instead.",
                    "property_declaration": "A binding inside an accessor body is a local."
                ]
            ),
            // A primary-constructor parameter becomes a property only when written `val`/`var`, which
            // the grammar marks with a `binding_pattern_kind` child.
            "class_parameter": .init(
                name: NamePath(.kind("simple_identifier")),
                requiredChildren: ["binding_pattern_kind"],
                knownIssue: "KotlinExtractor promotes it to a property but builds the member with no "
                    + "`location`, so nothing ties the declaration back to its line"
            )
        ]
    }

    private var ignored: [String: String] {
        [
            "package_header": "Sets the artifact's namespace; it declares no type of its own.",
            "primary_constructor": "Carries no name of its own — its `val`/`var` parameters are the "
                + "declarations, and each is checked as a `class_parameter`.",
            "parameter": "A parameter belongs to its member's signature, not to the type's members.",
            "type_parameter": "A generic parameter belongs to its declaration's signature.",
            "variable_declaration": "A property's name site, reached through its `property_declaration`; "
                + "inside a function body it names a local."
        ]
    }

    private var notDeclarations: Set<String> {
        [
            "additive_expression", "annotation", "assignment", "binding_pattern_kind", "call_expression",
            "call_suffix", "class_body", "class_modifier", "comparison_expression", "constructor_invocation",
            "control_structure_body", "delegation_specifier", "directly_assignable_expression",
            "enum_class_body", "for_statement", "function_body", "function_modifier",
            "function_value_parameters", "identifier", "if_expression", "infix_expression",
            "inheritance_modifier", "integer_literal", "interpolated_expression", "interpolated_identifier",
            "jump_expression", "member_modifier", "modifiers", "multiline_comment", "navigation_expression",
            "navigation_suffix", "nullable_type", "real_literal", "simple_identifier", "source_file",
            "statements", "string_content", "string_literal", "type_arguments", "type_constraint",
            "type_constraints", "type_identifier", "type_parameters", "type_projection", "user_type",
            "value_argument", "value_arguments", "visibility_modifier"
        ]
    }
}
