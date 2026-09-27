# Adding a Language

Teach Açaí a new language by writing a self-contained plugin — no changes to the engine.

## Overview

Açaí is deliberately **language-agnostic** at its core. The data model
([CodeArtifact](/documentation/acaicore/codeartifact)), the diagram generators, and the renderer
name no specific language; everything language-specific lives in a plugin and reaches the engine
only as data. That means you can add a language entirely from the outside — the built-in languages
are added the exact same way, with no privileged access.

A language plugin is one new module that brings five things together.

### 1. A parser

Conform a stateless `struct` to [CodeParser](/documentation/acaicore/codeparser): declare its
`fileExtensions`, implement `parse(source:fileName:)` to produce a
[CodeArtifact](/documentation/acaicore/codeartifact), and supply its `configuration`.

For anything other than Swift this is a Tree-sitter grammar plus the shared extraction layer in
[AcaiTreeSitter](/documentation/acaitreesitter/). That layer is split so you write as little as
possible: the recursive walks, the call-receiver decision tree, literal classification and the
declared-type pre-pass are shared values you construct once and keep, and what your plugin supplies
is a pair of narrow adapters — `CallSiteSyntax` and `AssignmentSyntax` — that answer questions about
a *single node*. Declaration bookkeeping and naming live one level up, in
[DeclarationBuilder](/documentation/acaicore/declarationbuilder), which your extractor **owns rather
than conforms to**.

`AcaiPython` is the worked example to copy; every other plugin follows the same shape.

#### The extractor's shape

Your extractor is a `struct` that owns every collaborator as a stored `let` (its
`DeclarationBuilder` is the one `var` — it accumulates as the walk proceeds) and builds all of them
**once**, in `init`, never per call site:

```swift
struct RubyExtractor {
    private let context: SourceFileContext
    private let callSites: CallSiteResolver
    private let assignments: AssignmentResolver
    private let fieldReads: FieldReadResolver
    private var declarations = DeclarationBuilder()

    init(source: String, fileName: String, root: Node) {
        let context = SourceFileContext(source: source, fileName: fileName)
        // Runs first: the collaborators below capture its result by value.
        let declaredTypeNames = TypeNamePrepass(declarationNodeTypes: ["class"])
            .names(in: root) { $0.child(byFieldName: "name")?.text(in: context) }

        self.context = context
        callSites = CallSiteResolver(
            syntax: RubyCallSiteSyntax(context: context, declaredTypeNames: declaredTypeNames)
        )
        assignments = AssignmentResolver(syntax: RubyAssignmentSyntax(context: context))
        fieldReads = FieldReadResolver(context: context, identifierTypes: ["identifier"])
        declarations.declaredTypeNames = declaredTypeNames
    }
}
```

Walk with `declarations`: nest a type with `let outer = declarations.enter(namespace: qualified)` /
`defer { declarations.leave(outer) }`, qualify ids with `declarations.qualifiedName(_:)`, record
supertype edges with `declarations.recordSupertypeRelationships(from:to:kind:)`, and finish with
`declarations.resolveRelationshipNames()` then `declarations.artifact(language:filePath:)`.

`CallSiteSyntax` and `AssignmentSyntax` are the two protocols your adapters conform to:

```swift
protocol CallSiteSyntax {
    var context: SourceFileContext { get }
    func resolveCallSite(_ node: Node, scope: CallSiteScope) -> CallSite?
    // Has a default (no locals); override to recognise typed/constructed local declarations.
    func localBindings(in body: Node, scope: CallSiteScope) -> [String: String]
}

protocol AssignmentSyntax {
    var context: SourceFileContext { get }
    func resolveAssignment(_ node: Node) -> VariableAssignment?
}
```

Both hold no mutable state and answer about one node at a time — the traversal lives in
`CallSiteResolver`/`AssignmentResolver`, which each wrap a syntax value. `CallSiteScope` is the
per-body lookup table (`knownProperties`, `knownTypeNames`, `knownPropertyNames`,
`knownMethodReturnTypes`) that keeps resolution conservative: a call site is only captured when its
receiver is provably a known type, everything else is dropped. Build one per member from
`MemberIndex(members:)` (`AcaiCore`), which turns a type's already-extracted members into those four
maps in one step:

```swift
CallSiteScope(members: MemberIndex(members: fields), knownTypeNames: declarations.declaredTypeNames)
```

Two more shared collaborators cover the rest of a declaration's syntax:

- `LiteralClassifier(context:literals:)`, given a `LiteralNodeTypes` table of your grammar's node
  types for booleans/numbers/strings/nil, classifies an assignment's right-hand side — falling back
  to `node.expressionSnippet(in:context)` (an opaque expression) when nothing matches.
- `ModifierClassifier(defaultAccessLevel:annotationNodeTypes:classify:postProcess:)` builds a
  declaration's access level, modifiers and annotations from its `modifiers` node in one call to
  `.modifierInfo(for:in:)` — `AcaiJVM`'s `JavaExtractor` and `KotlinExtractor` each hold their own
  instance with a different lookup table.

What remains — building a `TypeDeclaration` skeleton, shaping a `Member` from already-resolved
pieces, parameter lists, base-class/type-reference resolution — splits into stateless value types
that take their dependencies as stored `let`s (`RubyTypeDeclarationExtractor`,
`RubyMemberExtractor`, and so on), mirroring `AcaiPython`'s collaborators. A method that assembles a
`Member` takes a `Signature` (the declaration's own syntax) and a `ResolvedReferences` (the call
sites/assignments/field reads the caller already computed) rather than a long parameter list — see
`PythonMemberExtractor.callable(_:signature:references:)`. Anything with no state and no `Node`
belongs on a value: a method in an `extension` on `Node` or `String`, never a caseless enum of
`static func`s.

### 2. A `SourceLanguage` constant

Define it as an extension in your plugin — there are **no** built-in language constants in
[AcaiCore](/documentation/acaicore/), by design:

```swift
extension CodeArtifact.SourceLanguage {
    public static let ruby = CodeArtifact.SourceLanguage(rawValue: "ruby")
}
```

### 3. A `LanguageConfiguration`

Describe the language's quirks — primitive and collection types, any framework stereotypes, the
generated-code filter, and build-output directories to ignore. The engine resolves this from the
[LanguageRegistry](/documentation/acaicore/languageregistry), keyed on each artifact's language, so
the configuration is **injected**, never hard-coded into an agnostic module.

### 4. Build-system detector(s)

Conform to [BuildSystemDetector](/documentation/acaicore/buildsystemdetector) so
[AnalysisService](/documentation/acaicore/analysisservice) can find your language's source roots
(e.g. a manifest file at the project root).

### 5. Registration in the composition root

Add your parser and detector to `AnalysisService.standard` here in `AcaiLibrary` — the **only**
place that names the built-in languages. That keeps the agnostic boundary intact: the engine
stays free of language names, and external consumers register a language the same way.

### 6. A place in the shared test suites

Register your parser in `ParserConformanceTests` — which holds every language to the producer
contract documented on [CodeParser](/documentation/acaicore/codeparser) — and add one fixture to the
parser golden suite, which pins a parser's whole encoded artifact so a later refactor of the shared
layer has to reproduce your output exactly. Both are a few lines, and both then guard your plugin
without you maintaining them.

> The fastest path is the `/add-language` workflow, which scaffolds the module, the test target,
> and the registration. Read `Sources/AcaiPython/` first — it is the plugin shaped the way a new one
> should be.

## See Also

- [AcaiLibrary](/documentation/acailibrary/)
- <doc:GettingStarted>
- [CodeParser](/documentation/acaicore/codeparser)
- [LanguageConfiguration](/documentation/acaicore/languageconfiguration)
