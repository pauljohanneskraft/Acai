import Foundation

extension TypeDeclaration {

    /// The UML stereotype label for this type.
    ///
    /// When one of the type's annotations is a known marker (e.g. `@Entity` → `entity`), that
    /// stereotype wins; otherwise the kind-based stereotype (`TypeKind.stereotypeString`) is used.
    /// The annotation → stereotype map is supplied by the language's `LanguageConfiguration`. Pass
    /// `[:]` to use kind-based stereotypes only.
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
        var name = trimmingCharacters(in: .whitespacesAndNewlines)
        if name.hasPrefix("@") { name.removeFirst() }
        if let paren = name.firstIndex(of: "(") { name = String(name[..<paren]) }
        if let dot = name.lastIndex(of: ".") { name = String(name[name.index(after: dot)...]) }
        return name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
