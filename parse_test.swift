import Foundation
import UMLCSharp
import UMLTreeSitter

let parser = CSharpCodeParser()
let source = """
namespace MediaLibrary;

public class MediaItem : IPlayable {
    private readonly string _title;
    public string Title => _title;
    public MediaItem(string title) { _title = title; }
    public virtual void Play() {}
}
"""
let artifact = parser.parse(source: source, fileName: "test.cs")
print(artifact)
