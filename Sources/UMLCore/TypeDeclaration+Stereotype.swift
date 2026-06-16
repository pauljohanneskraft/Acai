import Foundation

extension TypeDeclaration {

    /// The UML stereotype label for this type.
    ///
    /// When `includeAnnotations` is set and one of the type's annotations is a known,
    /// unambiguous marker (e.g. `@Entity` → `entity`), that stereotype wins; otherwise the
    /// kind-based stereotype (`TypeKind.stereotypeString`) is used. This is never inferred —
    /// a stereotype only ever comes from a real annotation or a real `TypeKind`.
    public func stereotype(includeAnnotations: Bool = true) -> String? {
        if includeAnnotations {
            for annotation in annotations {
                if let stereotype = Self.annotationStereotypes[annotation.annotationName] {
                    return stereotype
                }
            }
        }
        return kind.stereotypeString
    }

    /// Known annotation → stereotype mappings, keyed by the bare annotation name (see
    /// `String.annotationName`), matched case-insensitively. Constant reference data.
    private static let annotationStereotypes: [String: String] = [
        "entity": "entity",
        "table": "entity",
        "embeddable": "embeddable",
        "repository": "repository",
        "service": "service",
        "controller": "controller",
        "restcontroller": "controller",
        "component": "component"
    ]
}

private extension String {

    /// This string reduced to a bare, comparable annotation name: a leading `@`, any argument
    /// list (`@Table(name="x")` → `table`) and any package qualifier
    /// (`jakarta.persistence.Entity` → `entity`) are stripped, then it is lowercased.
    var annotationName: String {
        var name = self
        if name.hasPrefix("@") { name.removeFirst() }
        if let paren = name.firstIndex(of: "(") { name = String(name[..<paren]) }
        if let dot = name.lastIndex(of: ".") { name = String(name[name.index(after: dot)...]) }
        return name.trimmingCharacters(in: .whitespaces).lowercased()
    }
}
