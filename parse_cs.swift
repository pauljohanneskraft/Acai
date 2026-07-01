import Foundation
import TreeSitterCSharp
import SwiftTreeSitter

let source = """
using System;
namespace MyNamespace {
    public class MyClass : BaseClass, IMyInterface {
        public int MyProperty { get; set; }
        private string myField;
        public void MyMethod(int param) {
            Console.WriteLine(param);
        }
    }
}
"""
let language = Language(language: tree_sitter_c_sharp())
let parser = Parser()
try! parser.setLanguage(language)
let tree = parser.parse(source)!

func printNode(_ node: Node, indent: String = "") {
    print("\(indent)\(node.nodeType)")
    for i in 0..<node.childCount {
        if let child = node.child(at: i) {
            printNode(child, indent: indent + "  ")
        }
    }
}
printNode(tree.rootNode!)
