# A modular, Tree-sitter-based `CodeParser` architecture

## Status and scope

This is a design document, not an implementation. It describes a from-scratch architecture for
the five Tree-sitter-backed language plugins in this package — `UMLJS` (TypeScript + JavaScript),
`UMLJVM` (Java + Kotlin), `UMLDart`, `UMLPython`, `UMLCFamily` (C + C++) — and the shared
`UMLTreeSitter` package they all depend on. `UMLSwift` is out of scope: it is built on SwiftSyntax,
never touches `UMLTreeSitter`, and nothing here changes it.

The document was produced without reading any existing Swift source under `Sources/` other than
`UMLCore` (per instruction) — the surrounding architecture is derived from `Package.swift`,
`UMLCore`'s public model (`CodeParser`, `CodeArtifact`, `TypeDeclaration`, `Member`, `CallSite`,
`VariableAssignment`, `FieldAccess`, `TypeReference`, `LanguageConfiguration`, …), and the
Tree-sitter Swift binding (`swift-tree-sitter`, a project dependency) plus three of the vendored
grammars (`tree-sitter-python`, `tree-sitter-kotlin`, `tree-sitter-cpp`), inspected directly to
validate the design's central assumption before committing to it.

An implementation plan (how the rewrite is sequenced, which language goes first, what happens to
any in-flight work) will be supplied separately. This document is the *shape* the implementation
should take.

---

## 1. The problem this design solves

`CodeParser` (`Sources/UMLCore/CodeParser.swift`) is a narrow, three-requirement protocol:

```swift
public protocol CodeParser: Sendable {
    var language: CodeArtifact.SourceLanguage { get }
    var fileExtensions: [String] { get }
    func parse(source: String, fileName: String) -> CodeArtifact
    var configuration: LanguageConfiguration { get }
}
```

Everything hard is inside `parse(source:fileName:)`. A conforming type must walk a source file and
produce a `CodeArtifact` whose `TypeDeclaration`/`Member`/`Relationship` graph satisfies a set of
non-negotiable **producer-contract invariants** documented on `CodeParser` itself:

- `TypeDeclaration.id == TypeDeclaration.qualifiedName`, namespace-qualified; a nested type's id is
  hierarchically prefixed by its parent's.
- `TypeDeclaration.name` is the **simple** (unqualified) name and must match the simple names used
  in `TypeReference.name` and `CallReceiver.type(_:)`.
- `TypeReference.name` is always simple — primitive/collection classification does exact-name
  matching against `LanguageConfiguration`.
- `TypeDeclaration.extensionOf` matches a target after generics are stripped.

Beyond structure, the model asks for **body-level analysis**: `Member.callSites`,
`Member.assignments`, `Member.fieldReads`, `Member.referencedTypeNames`,
`Member.cyclomaticComplexity`. The hardest single piece of this is `CallSite.receiver: CallReceiver`
— an 8-case enum (`Sources/UMLCore/CallSite.swift`) distinguishing `self` dispatch, a resolved
declared type, a free function, an unresolvable existential, and four *deferred* shapes
(`unresolvedTypeName`, `propertyChain`, `ownProperty`, `ownPropertyElement`, `ownMethodReturn`) that
`CodeArtifact.resolvingCallSiteReceivers()` (existing `UMLCore` enrichment, unaffected by this
design) resolves later, once the whole project's types are merged. **The parser's job is only to
classify a call's shape correctly from a single file — never to resolve across files.**

Five different Tree-sitter grammars (JS/TS, Java, Kotlin, Dart, Python, C, C++) must each produce
this same model. The architectural question this document answers: **how much of that logic is
duplicated five times, and how much is written once?**

The design's answer: as close to "written once" as the grammars allow, split along a line that
matches where genuine per-language variation actually lives — not where it's convenient to guess.

---

## 2. Validating the central assumption before designing around it

The tempting shortcut is a single flat data table per language — "here is this language's node
type name for a class declaration, here is its field name for a method's body" — consumed by one
generic Swift algorithm. Before committing to that shape, I checked it against three grammars
chosen to be maximally different: Python (whitespace-significant, no braces), Kotlin (JVM, but a
community grammar rather than a first-party one), and C++ (templates, operator overloading).

Reading `node-types.json` for each (in `.build/checkouts/tree-sitter-<lang>/src/`):

| Language | `class`-like node | fields | `call` node | fields |
|---|---|---|---|---|
| Python | `class_definition` | `body`, `name`, `superclasses`, `type_parameters` | `call` | `function`, `arguments` |
| C++ | `class_specifier` | `body`, `name` | `call_expression` | `function`, `arguments` |
| Kotlin | `class_declaration` | **(none)** | `call_expression` | **(none)** |

Kotlin's grammar (`fwcd/tree-sitter-kotlin`) defines **no fields whatsoever** for
`class_declaration`, `function_declaration`, `call_expression`, `navigation_expression`, or
`assignment` — confirmed against `grammar.js`:

```js
call_expression: $ => prec.left(PREC.POSTFIX, seq($._expression, $.call_suffix)),
navigation_expression: $ => prec.left(PREC.POSTFIX, seq($._expression, $.navigation_suffix)),
```

These are purely positional (`seq(...)`), not `field(...)`. A design expressed as "the callee is
in field X" cannot describe Kotlin at all — there is no field. **This kills the flat-lookup-table
approach outright**, and confirms the design must use something more expressive than a data table
for locating structure.

Tree-sitter's **query language** does not have this problem: a query pattern matches by field
*when the grammar defines one* and by positional/wildcard structure otherwise, and both forms
attach the *same* capture name. That is the concrete reason this design uses `.scm` queries as the
per-language adapter for structural extraction rather than a table of node/field-name strings.

---

## 3. The two extraction concerns, and why they're split

The design separates **structural extraction** from **body analysis**, because they have opposite
shapes and opposite amounts of legitimate per-language variation:

### 3.1 Structural extraction — declarative, per-language, but *shared consumer*

Types, members (signatures only), enum cases, generics/constraints, namespaces, nesting,
annotations. Each of these is a **bounded** shape: a class declaration has a name, maybe a
superclass list, maybe type parameters, a body — the grammar tells you exactly what's there, once,
non-recursively. This is precisely the shape Tree-sitter queries are good at, and precisely the
shape GitHub's and nvim-treesitter's cross-language `tags.scm` convention already proves scales
across dozens of grammars for structural/definition extraction (a real, working precedent — not a
speculative one).

So: **one `.scm` query file per language**, each written against that language's actual grammar
(field-based for Python/C++, positional for Kotlin — the query author handles that, not the Swift
consumer), each emitting the same fixed vocabulary of capture names. **One generic Swift assembler
in `UMLTreeSitter`** turns that capture stream into `TypeDeclaration`/`Member`/`EnumCase`, for every
language, unconditionally.

This is *not* small per-language content. `LanguageConfiguration` already tells you why: this
project's model is deep (access levels, a dozen distinct modifiers, generic constraints, enum raw
values *and* associated values, narrowed setter access, optionality, arrays, annotations-as-
stereotypes). A `.scm` file expressing all of that for, say, Kotlin's grammar is genuinely
substantial — closer to a few hundred lines than fifteen. That size lives in the plugin, as data,
which is exactly where `LanguageConfiguration` already puts equivalent per-language depth.

### 3.2 Body analysis — imperative, shared algorithm, narrow per-language adapter

Calls, assignments, field reads, `CallReceiver` classification, cyclomatic complexity. These are
**unbounded and recursive**: `a.b.c.d().e()` has no fixed depth, and classifying its receiver
requires knowing things a query has no access to at match time — *which identifiers are this
type's own stored properties*, *what is this language's spelling of "self"* (a keyword node in
some grammars, a bare identifier by convention in Python's), *is this capitalized identifier a
type declared elsewhere in this same file*. None of that can be pre-computed into a `.scm` pattern
or a static table; it depends on the file's own already-assembled structural data.

So this half stays **imperative Swift, written once, in `UMLTreeSitter`** — the actual recursive
walk, the actual `CallReceiver` case-selection state machine — parameterized by the *smallest*
adapter that can express "is/decompose this node" in terms of any of the five grammars:

```swift
public protocol TreeSitterExpressionGrammar: Sendable {
    func callParts(of node: Node) -> (callee: Node, arguments: [Node])?
    func memberAccessParts(of node: Node) -> (object: Node, memberName: String)?
    func assignmentParts(of node: Node) -> (target: Node, op: VariableAssignment.Operator, value: Node)?
    func isSelfReference(_ node: Node) -> Bool
    func isConstruction(_ node: Node) -> Bool
    func isDecisionPoint(_ node: Node) -> Bool
    func identifierText(of node: Node) -> String?
}
```

Seven requirements, each answering a yes/no or decompose-this-one-node question — a legitimate
multi-method protocol (not the single-constant mixin this codebase's conventions warn against),
implemented once per language in terms of that grammar's real node types. This is where Kotlin's
positional `call_expression`/`navigation_expression` and Python's field-based `call`/`attribute`
each get one small, honest implementation — six or seven short methods, not a sprawling table —
while every recursive algorithm that *consumes* the adapter is shared.

This split directly targets the historical failure mode this design exists to prevent: if
`CallReceiver` classification is data five times, a bug fix is five fixes; if it is code once, a
bug fix is one fix, inherited by all five languages the next time they're built.

---

## 4. The shared capture-name vocabulary (structural queries)

Every language's `.scm` file must emit these capture names (dotted, following Tree-sitter's own
`@parent.child` convention); the assembler in `UMLTreeSitter` never needs to know which grammar
produced them.

| Capture | Meaning | Consumed by |
|---|---|---|
| `@type` | a type declaration's whole node (for nesting/byte-range containment) | `TypeDeclarationAssembler` |
| `@type.name` | the simple name | id/qualifiedName computation |
| `@type.kind` | keyword text (`"class"`, `"struct"`, …) — mapped via `TypeStructureVocabulary.kindKeywords` | `TypeKind` |
| `@type.access` | keyword text — mapped via `accessKeywords` | `AccessLevel` |
| `@type.modifier` | keyword text, repeatable — mapped via `modifierKeywords` | `[Modifier]` |
| `@type.supertype` | one per inherited type/conformance | `[TypeReference]` |
| `@type.generic.param` / `@type.generic.constraint` | generic parameter list | `[GenericParameter]` |
| `@type.namespace` | enclosing package/namespace text, when the grammar has one | qualified-name prefix |
| `@type.annotation` | raw annotation/attribute text, repeatable | `[String]` |
| `@type.extensionOf` | the extended type's name, extension/category declarations only | `extensionOf` |
| `@member` | a member's whole node | `MemberSignatureAssembler` |
| `@member.name`, `.kind`, `.access`, `.setAccess`, `.modifier`, `.type`, `.annotation` | mirrors the `@type.*` set, member-scoped | `Member` fields |
| `@member.param` / `.param.name` / `.param.type` / `.param.default` / `.param.variadic` | parameter list | `[Parameter]` |
| `@member.body` | the member's body node, handed to body analysis (§3.2) unparsed | `MemberBodyWalker` |
| `@enumCase`, `.name`, `.rawValue`, `.assocValue` | enum case list | `[EnumCase]` |

Two grammars, two shapes, same capture names — illustrating the point from §2. Python (field-based):

```scheme
(class_definition
  name: (identifier) @type.name
  superclasses: (argument_list (identifier) @type.supertype)?) @type
```

Kotlin (positional — no fields to anchor on, so the pattern matches by child order/shape instead):

```scheme
(class_declaration
  (simple_identifier) @type.name
  (delegation_specifiers (constructor_invocation (user_type (simple_identifier) @type.supertype)))?) @type
```

Both patterns produce `@type`, `@type.name`, `@type.supertype` — the assembler that turns those
into a `TypeDeclaration` is identical Swift code for both.

`#set!` directives (already supported by `swift-tree-sitter`'s `Predicate` type, which parses
`set!`/`eq?`/`match?`/`any-of?` and exposes per-capture `metadata: [String: String]` on
`QueryCapture`) let a query author attach semantic tags inline, e.g. tagging a capture's kind
without a separate lookup, or asserting `(#any-of? @call.receiverText "self" "cls")` to classify
Python's convention-based self-reference *inside the query* rather than in Swift. Where a
predicate can express a classification declaratively, prefer it — it keeps the Swift-side adapter
(§3.2) limited to the handful of things a query genuinely cannot see (cross-node contextual lookup
against the file's own already-assembled member list).

---

## 5. `UMLTreeSitter` — full type inventory

Every type below is deliberately small: one responsibility, a handful of stored properties, method
count nowhere near 20. Composition replaces one large extractor. Expensive objects (`Query`,
`Language`) are constructed exactly once, as `let` stored properties set in a language plugin's
`init()` — never recomputed inside a computed property — because `AnalysisService`
(`Sources/UMLCore/AnalysisService.swift`) holds each `CodeParser` value for an entire run and calls
`parse` on it once per source file, so the cost of compiling a query is naturally amortized and
must not be paid again per file.

### 5.1 Parsing and diagnostics (zero language-specific logic)

```swift
/// One parsed file: its tree, root node, and raw text (needed for a `Predicate.Context`
/// text provider and for slicing identifier/literal text out of nodes).
public struct ParsedSource: Sendable {
    public let tree: Tree
    public let rootNode: Node
    public let text: String
    public let fileName: String
}

/// Wraps `SwiftTreeSitter.Parser` set up for one grammar. Owns: the compiled `Language`.
public struct SourceFileParser: Sendable {
    private let language: Language
    public init(language: Language)
    public func parse(source: String, fileName: String) -> ParsedSource?
}

/// Walks a tree for `ERROR`/`MISSING` nodes. Stateless; the same instance works for every
/// grammar since `Node.isMissing`/`hasError` are grammar-agnostic Tree-sitter primitives.
///
/// Reports *specific* offending nodes rather than trusting the root node's aggregate
/// `hasError`, which is known to false-positive on at least one grammar in this project
/// (tree-sitter-kotlin, terse single-line class bodies) — walking to the actual ERROR/MISSING
/// nodes avoids inheriting that false positive, and test fixtures for this collector should
/// prefer multi-line bodies for the same reason.
public struct ParseDiagnosticsCollector: Sendable {
    public init()
    public func diagnostics(in source: ParsedSource) -> [ParseDiagnostic]
}
```

### 5.2 Query execution

```swift
/// A compiled `.scm` query plus the language it was compiled against. Construction can throw
/// (`QueryError`, surfaced from `SwiftTreeSitter.Query.init`) since malformed query source is
/// a plugin authoring bug, not a runtime condition.
public struct StructuralQuery: Sendable {
    private let query: Query
    public init(language: Language, source: String) throws
    public func matches(in source: ParsedSource) -> [QueryMatch]
}
```

### 5.3 Structural assembly

```swift
/// Per-language keyword data — the one place a flat lookup table *is* the right tool, because
/// unlike node shape, keyword-to-model-case mapping has no positional ambiguity to resolve.
public struct TypeStructureVocabulary: Sendable {
    public var kindKeywords: [String: TypeKind]
    public var modifierKeywords: [String: Modifier]
    public var accessKeywords: [String: AccessLevel]
    public var defaultAccessLevel: AccessLevel
    public var namespaceSeparator: String
    public init(
        kindKeywords: [String: TypeKind],
        modifierKeywords: [String: Modifier],
        accessKeywords: [String: AccessLevel],
        defaultAccessLevel: AccessLevel,
        namespaceSeparator: String
    )
}

/// `@type.*` captures → `[TypeDeclaration]`, including nesting (by capture byte-range
/// containment — a `@type` capture whose range is inside another's is a nested type, prefixed
/// by the parent's id) and the id == qualifiedName producer-contract invariant.
public struct TypeDeclarationAssembler: Sendable {
    private let vocabulary: TypeStructureVocabulary
    public init(vocabulary: TypeStructureVocabulary)
    public func assemble(
        matches: [QueryMatch],
        members: [Member],       // pre-assembled by MemberSignatureAssembler, grouped by owning @type
        enumCases: [EnumCase],   // pre-assembled by EnumCaseAssembler, grouped by owning @type
        source: ParsedSource
    ) -> [TypeDeclaration]
}

/// `@member.*` captures → `[Member]` (signature only — no body analysis; that's §5.5). Split out
/// of `TypeDeclarationAssembler` so neither type's method count grows unbounded.
public struct MemberSignatureAssembler: Sendable {
    private let vocabulary: TypeStructureVocabulary
    public init(vocabulary: TypeStructureVocabulary)
    public func assemble(matches: [QueryMatch], source: ParsedSource) -> [Member]
}

/// `@enumCase.*` captures → `[EnumCase]`.
public struct EnumCaseAssembler: Sendable {
    public init()
    public func assemble(matches: [QueryMatch], source: ParsedSource) -> [EnumCase]
}

/// Normalizes a raw type-reference string to the producer contract's required "simple name"
/// (strip generic arguments `Foo<T>` → `Foo`, strip namespace qualifiers `a.b.Foo` → `Foo`).
/// A single shared implementation so no plugin reimplements this rule slightly differently.
public struct SimpleTypeName: Sendable {
    public let raw: String
    public init(_ raw: String)
    public var simpleName: String { get }
}
```

### 5.4 Cross-referencing data for body analysis

```swift
/// Built once per type, right after its `[Member]` is assembled — the only context the body
/// analyzer needs to classify a receiver without looking outside the current file.
public struct KnownMemberIndex: Sendable {
    public let enclosingTypeName: String
    public let storedPropertyNames: Set<String>
    public let arrayTypedPropertyNames: Set<String>
    public let methodReturnTypesByName: [String: String]
    public init(enclosingTypeName: String, members: [Member])
}
```

### 5.5 Body analysis (the shared algorithm)

```swift
public protocol TreeSitterExpressionGrammar: Sendable {
    func callParts(of node: Node) -> (callee: Node, arguments: [Node])?
    func memberAccessParts(of node: Node) -> (object: Node, memberName: String)?
    func assignmentParts(of node: Node) -> (target: Node, op: VariableAssignment.Operator, value: Node)?
    func isSelfReference(_ node: Node) -> Bool
    func isConstruction(_ node: Node) -> Bool
    func isDecisionPoint(_ node: Node) -> Bool
    func identifierText(of node: Node) -> String?
}

/// Every `CallReceiver` case is decided in exactly one place. Takes only the already-peeled
/// shape of a call's receiver chain (never a raw `Node`) so it has zero grammar dependency —
/// this type is identical for all five languages, which is the whole point of this design.
public struct CallReceiverClassifier: Sendable {
    public init()
    public func classify(
        headKind: ReceiverHeadKind,      // .selfKeyword / .bareIdentifier(String) / .capitalizedIdentifier(String)
        hops: [String],
        knownTypeNames: Set<String>,     // types declared elsewhere in this same file
        knownMembers: KnownMemberIndex
    ) -> CallReceiver
}

/// Recursive walk of one member's body. Peels `a.b.c()` into (head, hops, methodName) using
/// only `TreeSitterExpressionGrammar` — no node-type strings — and asks `CallReceiverClassifier`
/// to decide each `CallSite.receiver`. Also emits `[VariableAssignment]`, `[FieldAccess]`,
/// `referencedTypeNames` (via `isConstruction`) from the same single walk.
public struct MemberBodyWalker: Sendable {
    private let grammar: any TreeSitterExpressionGrammar
    private let classifier: CallReceiverClassifier
    public init(grammar: any TreeSitterExpressionGrammar)
    public func walk(body: Node, source: ParsedSource, knownMembers: KnownMemberIndex) -> BodyAnalysisResult
}

public struct BodyAnalysisResult: Sendable {
    public let callSites: [CallSite]
    public let assignments: [VariableAssignment]
    public let fieldReads: [FieldAccess]
    public let referencedTypeNames: [String]
}

/// Kept separate from `MemberBodyWalker` (own single responsibility) even though both walk the
/// same body node — one counts decision points, the other classifies calls; fusing them would
/// grow one type past the point of being easy to reason about.
public struct CyclomaticComplexityCounter: Sendable {
    private let grammar: any TreeSitterExpressionGrammar
    public init(grammar: any TreeSitterExpressionGrammar)
    public func count(body: Node) -> Int
}
```

### 5.6 Composition root for one file

```swift
/// Pure data: the four things one language plugin owns. No methods — a language's `init()`
/// builds exactly one of these, once, and every `parse` call reuses it.
public struct TreeSitterLanguagePlugin: Sendable {
    public let grammar: Language
    public let structuralQuery: StructuralQuery
    public let vocabulary: TypeStructureVocabulary
    public let expressionGrammar: any TreeSitterExpressionGrammar
    public init(
        grammar: Language,
        structuralQuery: StructuralQuery,
        vocabulary: TypeStructureVocabulary,
        expressionGrammar: any TreeSitterExpressionGrammar
    )
}

/// The one orchestrator a `CodeParser.parse` calls. Contains no extraction logic of its own —
/// only sequencing of the collaborators above — so it stays a thin facade, not a god class.
public struct TreeSitterSourceFileExtractor: Sendable {
    private let plugin: TreeSitterLanguagePlugin
    public init(plugin: TreeSitterLanguagePlugin)
    public func extract(source: String, fileName: String, language: CodeArtifact.SourceLanguage) -> CodeArtifact
}
```

`TreeSitterSourceFileExtractor.extract` sequences, in order: `SourceFileParser.parse` →
`ParseDiagnosticsCollector.diagnostics` → `StructuralQuery.matches` → `MemberSignatureAssembler` /
`EnumCaseAssembler` → `TypeDeclarationAssembler` → for each member with a `@member.body` capture,
build a `KnownMemberIndex` from its owning type and run `MemberBodyWalker` +
`CyclomaticComplexityCounter` → assemble the final `CodeArtifact`.

---

## 6. Per-language plugin shape

Using `UMLPython` as the illustrative example (structurally the simplest of the five: no
positional-only quirk like Kotlin's, no dual-language target like `UMLJVM`/`UMLCFamily`):

```swift
public struct PythonParser: CodeParser {
    public let language = CodeArtifact.SourceLanguage.python   // extension defined in this target
    public let fileExtensions = ["py", "pyi"]
    public let configuration: LanguageConfiguration            // unchanged shape/role vs. today

    private let plugin: TreeSitterLanguagePlugin

    public init() {
        configuration = LanguageConfiguration(/* primitives, collections, entry points, … */)
        plugin = TreeSitterLanguagePlugin(
            grammar: Language(language: tree_sitter_python()),
            structuralQuery: try! StructuralQuery(
                language: Language(language: tree_sitter_python()),
                source: PythonStructuralQuery.source   // this language's .scm, as instance data
            ),
            vocabulary: TypeStructureVocabulary(
                kindKeywords: ["class": .class],
                modifierKeywords: ["staticmethod": .static, "classmethod": .class /* … */],
                accessKeywords: [:],                    // Python has no access keywords
                defaultAccessLevel: .public,
                namespaceSeparator: "."
            ),
            expressionGrammar: PythonExpressionGrammar()
        )
    }

    public func parse(source: String, fileName: String) -> CodeArtifact {
        TreeSitterSourceFileExtractor(plugin: plugin).extract(source: source, fileName: fileName, language: language)
    }
}

/// The ~7-method adapter, in terms of Python's actual (field-based) grammar.
struct PythonExpressionGrammar: TreeSitterExpressionGrammar {
    func callParts(of node: Node) -> (callee: Node, arguments: [Node])? {
        guard node.nodeType == "call", let callee = node.child(byFieldName: "function") else { return nil }
        let args = node.child(byFieldName: "arguments")?.namedChildren ?? []
        return (callee, args)
    }
    func memberAccessParts(of node: Node) -> (object: Node, memberName: String)? {
        guard node.nodeType == "attribute",
              let object = node.child(byFieldName: "object"),
              let attr = node.child(byFieldName: "attribute") else { return nil }
        return (object, /* text of attr */ "")
    }
    // assignmentParts / isSelfReference / isConstruction / isDecisionPoint / identifierText: similarly
    // short, each one grammar-shape check + field/child lookup.
}
```

Kotlin's adapter (inside `UMLJVM`, alongside Java's) implements the same seven methods positionally
instead of by field, per the grammar facts from §2 — the shape of that adapter differs from
Python's, but `MemberBodyWalker`/`CallReceiverClassifier`/`CyclomaticComplexityCounter` in
`UMLTreeSitter` do not change at all between the two.

What every plugin owns, concretely:

1. A `CodeArtifact.SourceLanguage` extension constant.
2. Its `.scm` structural query text — real per-language content (§3.1), embedded as instance data
   (a `let` the parser passes to `StructuralQuery.init` once), never a static namespace.
3. One `TypeStructureVocabulary` value.
4. One `TreeSitterExpressionGrammar` conformance (§3.2) — the narrow, honest adapter.
5. The `CodeParser` conformance itself, per the sketch above.
6. Its existing build-system detector(s) — entirely unaffected by this design; project discovery
   is a separate concern from parsing and isn't touched here.

`UMLJVM` and `UMLCFamily` each host two `CodeParser` conformances today (Java+Kotlin, C+C++) and
continue to; each of the two still gets its own query file, vocabulary, and expression-grammar
adapter (the grammars differ too much to share those), while the target boundary itself (and the
shared build-system detector inside it) is unchanged.

---

## 7. What this design deliberately does not change

- `UMLCore`'s model and enrichment pipeline (`CodeArtifact.resolvingCallSiteReceivers()`,
  `resolvingExtensions()`, `filteringGeneratedTypes`, `LanguageRegistry`, `TypeIdentityResolver`) —
  none of it. This design only concerns how a `CodeParser` conformance is *built*, not the contract
  it must satisfy or what happens to its output afterward.
- Project discovery / build-system detection (`BuildSystemDetector`, `ProjectDiscovery`,
  `FallbackDetector`) — a language plugin's detector(s) are unrelated to how it parses a file once
  found, and are untouched.
- `UMLSwift` — SwiftSyntax-based, never depended on `UMLTreeSitter`, out of scope entirely.
- The public product/target graph in `Package.swift` — every plugin still depends on `UMLCore` +
  `UMLTreeSitter` + its own grammar product(s), exactly as today; only what's *inside* each target
  changes.

---

## 8. Risks and open edges called out honestly

- **Unbounded chain depth in queries is not attempted.** `MemberBodyWalker`'s recursive peel
  handles `a.b.c.d()` regardless of depth because it's imperative Swift, not a fixed-shape query
  pattern — this is precisely why body analysis isn't pushed into `.scm` queries even though
  structural extraction is.
- **`#set!`/predicate-based classification (§4) trades query complexity for Swift complexity.**
  Where a language's convention can be expressed as a query predicate (e.g. Python's `self`/`cls`
  recognized by identifier text via `#any-of?`), doing it in the query keeps
  `TreeSitterExpressionGrammar.isSelfReference` trivial for that language; a grammar that can't
  express it declaratively falls back to `isSelfReference` checking the node's actual self-keyword
  type. Both paths are legitimate; the per-language query author picks based on their grammar.
- **Cyclomatic complexity and body walking both traverse the member body** — two separate
  traversals rather than one fused pass, by deliberate choice (§5.5) to keep both types small; if
  this turns out to be a real performance concern at scale, it's a candidate for later fusion
  behind the same two public APIs, not a reason to merge the types now.
- **This document does not fix an implementation order.** Which language plugin is rewritten first,
  how much of `UMLTreeSitter` is built before the first plugin lands, and what (if anything) happens
  to any currently in-flight branch work are implementation-planning questions, addressed
  separately from this design.
