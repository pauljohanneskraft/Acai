import Foundation

extension TypeDeclaration {

    /// The UML stereotype label for this type.
    ///
    /// When `annotationStereotypes` is non-empty and one of the type's annotations is a known,
    /// unambiguous marker (e.g. `@Entity` → `entity`), that stereotype wins; otherwise the
    /// kind-based stereotype (`TypeKind.stereotypeString`) is used. This is never inferred —
    /// a stereotype only ever comes from a real annotation or a real `TypeKind`.
    ///
    /// The annotation → stereotype map is supplied by the language's `LanguageConfiguration`
    /// (e.g. Spring/JPA markers live in the JVM language target), so this core stays agnostic of
    /// any framework's conventions. Pass `[:]` to use kind-based stereotypes only.
    public func stereotype(annotationStereotypes: [String: String] = [:]) -> String? {
        for annotation in annotations {
            if let stereotype = annotationStereotypes[annotation.annotationName] {
                return stereotype
            }
        }
        return kind.stereotypeString
    }
}

extension String {

    /// This string reduced to a bare, comparable annotation name: a leading `@`, any argument
    /// list (`@Table(name="x")` → `table`) and any package qualifier
    /// (`jakarta.persistence.Entity` → `entity`) are stripped, then it is lowercased.
    var annotationName: String {
        // Trim leading/trailing whitespace and newlines up front so a leading "@" is reliably
        // detected and multi-line / formatted annotations still match.
        var name = trimmingCharacters(in: .whitespacesAndNewlines)
        if name.hasPrefix("@") { name.removeFirst() }
        if let paren = name.firstIndex(of: "(") { name = String(name[..<paren]) }
        if let dot = name.lastIndex(of: ".") { name = String(name[name.index(after: dot)...]) }
        return name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
