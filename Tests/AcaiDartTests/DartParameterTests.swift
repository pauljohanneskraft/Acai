import Testing
@testable import AcaiDart
@testable import AcaiCore

@Suite("Dart: Constructor Parameters")
struct DartParameterTests {
    let parser = DartCodeParser()

    /// `this.artist` states no type of its own — it takes the field's — and `[this.album]` is an
    /// optional positional parameter. Both used to be lost: the first appeared untyped, the second
    /// not at all, so the rendered constructor signature was shorter than the source's.
    @Test func fieldFormalAndOptionalPositionalParameters() {
        let source = """
        class Song {
          Song(String title, this.artist, [this.album]);

          final String artist;
          final String? album;
        }
        """
        let song = parser.parse(source: source, fileName: "song.dart").types.first { $0.name == "Song" }
        let initializer = song?.members.first { $0.kind == .initializer }
        #expect(initializer?.parameters.map(\.internalName) == ["title", "artist", "album"])
        let byName = Dictionary(
            uniqueKeysWithValues: (initializer?.parameters ?? []).map { ($0.internalName, $0.type) })
        #expect(byName["artist"]??.name == "String")
        #expect(byName["album"]??.name == "String")
        #expect(byName["album"]??.isOptional == true)
    }

    /// A named parameter list (`{…}`) is the other `optional_formal_parameters` form.
    @Test func namedParametersAreReported() {
        let source = """
        class Song {
          int rate({int stars = 3, String? note}) => stars;
        }
        """
        let rate = parser.parse(source: source, fileName: "song.dart").types.first?
            .members.first { $0.name == "rate" }
        #expect(rate?.parameters.map(\.internalName) == ["stars", "note"])
    }
}
