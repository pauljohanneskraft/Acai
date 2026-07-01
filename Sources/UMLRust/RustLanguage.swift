import UMLCore

extension CodeArtifact.SourceLanguage {
    public static let rust = CodeArtifact.SourceLanguage(rawValue: "rust")
}

extension RustCodeParser {
    public var configuration: LanguageConfiguration {
        LanguageConfiguration(
            primitiveTypeNames: [
                "()", "bool", "char", "str", "String",
                "i8", "i16", "i32", "i64", "i128", "isize",
                "u8", "u16", "u32", "u64", "u128", "usize",
                "f32", "f64"
            ],
            collectionTypeNames: [
                "Vec", "VecDeque", "LinkedList", "BinaryHeap",
                "HashMap", "BTreeMap", "HashSet", "BTreeSet"
            ],
            excludedDirectories: [".cargo", "target"]
        )
    }
}
