import Testing
import UMLCore
import UMLDiagram
@testable import UMLRust

@Suite("Rust: Type Tests")
struct RustTypeTests {
    let parser = RustCodeParser()

    @Test func structsEnumsTraitsAndTypeAliases() {
        let source = """
        pub trait Playable {
            fn play(&self);
        }

        pub enum Genre {
            Pop,
            Rock,
        }

        pub struct MediaItem {
            pub title: String,
            pub genre: Genre,
        }

        pub type ItemMap = Vec<MediaItem>;

        impl Playable for MediaItem {
            fn play(&self) {}
        }
        """

        let artifact = parser.parse(source: source, fileName: "media.rs")
        let playable = artifact.types.first { $0.name == "Playable" }
        let genre = artifact.types.first { $0.name == "Genre" }
        let mediaItem = artifact.types.first { $0.name == "MediaItem" }
        let alias = artifact.types.first { $0.name == "ItemMap" }

        #expect(playable?.kind == .trait)
        #expect(genre?.kind == .enum)
        #expect(genre?.enumCases.map(\.name) == ["Pop", "Rock"])
        #expect(mediaItem?.kind == .struct)
        #expect(mediaItem?.members.map(\.name) == ["title", "genre", "play"])
        #expect(alias?.kind == .typeAlias)
        #expect(artifact.relationships.contains {
            $0.kind == .conformance && $0.source == "MediaItem" && $0.target == "Playable"
        })
    }

    @Test func modulesQualifyTypeIdentity() {
        let source = """
        mod billing {
            pub struct Account {
                pub id: String,
            }
        }
        """

        let artifact = parser.parse(source: source, fileName: "mod.rs")
        let account = artifact.types.first { $0.name == "Account" }
        #expect(account?.id == "billing.Account")
        #expect(account?.qualifiedName == "billing.Account")
    }

    @Test func collectionsAndOptionsPreserveElementTypes() {
        let source = """
        pub struct MediaItem {}

        pub struct Library {
            pub items: Vec<MediaItem>,
            pub featured: Option<MediaItem>,
        }
        """

        let artifact = parser.parse(source: source, fileName: "library.rs")
        let library = artifact.types.first { $0.name == "Library" }
        let items = library?.members.first { $0.name == "items" }
        let featured = library?.members.first { $0.name == "featured" }

        #expect(items?.type?.name == "Vec")
        #expect(items?.type?.genericArguments.map(\.name) == ["MediaItem"])
        #expect(items?.type?.isArray == true)
        #expect(featured?.type?.name == "MediaItem")
        #expect(featured?.type?.isOptional == true)
    }
}
