---
name: add-language
description: Add a new source-language plugin to the Acai tool (new Tree-sitter dependency, plugin target + test target, a SourceLanguage constant, a CodeParser with its LanguageConfiguration and build-system detector, and registration in the AcaiLibrary composition root). Use when the user wants to support parsing a new programming language.
---

# Add a language plugin

A language is a **self-contained plugin**: its own target owning the parser, its `SourceLanguage`
constant, its `LanguageConfiguration` (the language's quirks), and its build-system detector(s).
The agnostic engine (`AcaiCore`, `AcaiDiagram`, `AcaiLibrary`'s agnostic surface) must never name or
special-case a language — all language/framework data lives in the plugin and reaches the engine by
injection. See `CLAUDE.md` → "The language-agnostic boundary".

Use `Sources/AcaiPython/` as the reference: a standalone Tree-sitter plugin with a `SourceLanguage`
constant, a `LanguageConfiguration`, a `PythonDetector`, and — the part to copy most closely — an
extractor composed of small injected collaborators rather than one type doing everything. See
`Sources/AcaiDart/` only for a `GeneratedCodeFilter` example; its extraction is the older shape.

Adding language `<Lang>` (e.g. `Rust`) means, in order:

1. **Dependency** — in `Package.swift`, add the Tree-sitter grammar package to `dependencies`
   (search github.com/tree-sitter for the official grammar; pin `from:` a released version, only use
   `branch:` if no tags exist, as Dart does).

2. **Library product + target** — add `.library(name: "Acai<Lang>", targets: ["Acai<Lang>"])` to
   `products`, and a `.target` named `Acai<Lang>` depending on `"AcaiCore"`, `"AcaiTreeSitter"`, and
   `.product(name: "TreeSitter<Lang>", package: "...")`. (For a JVM-family language, extend the
   existing `AcaiJVM` target instead of making a new one.)

3. **Test target** — add `.testTarget(name: "Acai<Lang>Tests", dependencies: ["Acai<Lang>", "AcaiCore"])`.

4. **Parser** — create `Sources/Acai<Lang>/<Lang>CodeParser.swift`: a stateless
   `public struct <Lang>CodeParser: CodeParser` exposing `language`, `fileExtensions` (lowercase, no
   dot), `parse(source:fileName:) -> CodeArtifact`, and `configuration`. Hold the
   `TreeSitterGrammar` as a `let` on the parser — it is loaded once per run, not once per file — and
   implement `parse` as `grammar.parse(source:fileName:) { root in … }`, which owns the
   load-failure, empty-tree and parse-diagnostics handling; the closure only builds the artifact.

5. **Extraction** — use `Sources/AcaiPython/` as the reference; every plugin is composed the same
   way. The extractor is a `struct` that owns every collaborator as a stored `let` (its
   `DeclarationBuilder` is the one `var`, since it accumulates as the walk proceeds) and builds all
   of them **once**, in `init` — never per call site:

   ```swift
   struct <Lang>Extractor {
       private let context: SourceFileContext
       private let callSites: CallSiteResolver
       private let assignments: AssignmentResolver
       private let fieldReads: FieldReadResolver
       private var declarations = DeclarationBuilder()

       init(source: String, fileName: String, root: Node) {
           let context = SourceFileContext(source: source, fileName: fileName)
           // Runs before the collaborators below, which capture its result by value.
           let declaredTypeNames = TypeNamePrepass(declarationNodeTypes: ["class_declaration"])
               .names(in: root) { $0.child(byFieldName: "name")?.text(in: context) }

           self.context = context
           callSites = CallSiteResolver(
               syntax: <Lang>CallSiteSyntax(context: context, declaredTypeNames: declaredTypeNames)
           )
           assignments = AssignmentResolver(syntax: <Lang>AssignmentSyntax(context: context))
           fieldReads = FieldReadResolver(context: context, identifierTypes: ["identifier"])
           declarations.declaredTypeNames = declaredTypeNames
       }
   }
   ```

   - Your extractor owns a `DeclarationBuilder` (`AcaiCore`) — the types, relationships,
     freestanding functions, globals, declared type names and namespace discipline — and conforms to
     **nothing**. Nest a type with `let outer = declarations.enter(namespace: qualified)` /
     `defer { declarations.leave(outer) }`; qualify ids with `declarations.qualifiedName(_:)`; record
     supertype edges with `declarations.recordSupertypeRelationships(from:to:kind:)`; finish with
     `declarations.resolveRelationshipNames()` then `declarations.artifact(language:filePath:)`.
   - Write two small stateless adapters, mirroring `PythonCallSiteSyntax` / `PythonAssignmentSyntax`,
     conforming to the two narrow protocols `AcaiTreeSitter` declares:

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

     Both answer questions about a *single node* and hold no mutable state; never write a traversal
     in one — the recursion lives in `CallSiteResolver`/`AssignmentResolver`, which each wrap a
     syntax value. `CallSiteScope` is the per-body lookup table (`knownProperties`, `knownTypeNames`,
     `knownPropertyNames`, `knownMethodReturnTypes`) that keeps resolution conservative — a call site
     is only captured when its receiver is provably a known type, everything else is dropped. Build
     one per member from `MemberIndex(members:)` (`AcaiCore`), which turns a type's already-extracted
     members into those four maps in one step:
     `CallSiteScope(members: MemberIndex(members: fields), knownTypeNames: declarations.declaredTypeNames)`.
   - Construct each shared resolver **once**, in the extractor's `init`, and store it:
     `CallSiteResolver(syntax:)`, `AssignmentResolver(syntax:)`,
     `FieldReadResolver(context:identifierTypes:)`, and — if your grammar names its member-access
     fields — `MemberCallResolver(context:grammar:)` with a
     `MemberCallGrammar(selfNodeType:memberAccessType:memberField:)`. Rebuilding a collaborator per
     call site is the specific anti-pattern this shape replaced.
   - For assignment right-hand sides, classify literals with `LiteralClassifier(context:literals:)`
     against a `LiteralNodeTypes(boolean:numeric:string:nilLiteral:interpolationChildTypes:)` table of
     your grammar's node types, falling back to `node.expressionSnippet(in:context)` (an opaque
     expression) when nothing matches.
   - For modifier/access-level parsing, build one
     `ModifierClassifier(defaultAccessLevel:annotationNodeTypes:classify:postProcess:)` and call
     `.modifierInfo(for: modifiersNode, in: context)` per declaration — `JavaExtractor` and
     `KotlinExtractor` each hold one instance with their own lookup table.
   - Reach for the shared pieces before writing your own: `TypeNamePrepass` (the declared-type
     pre-pass, run in `init` before its result is captured), `MemberIndex` / `UnambiguousTypeNames`
     (property and return-type maps), `LiteralClassifier` + `LiteralNodeTypes`, `ModifierClassifier`,
     `ParseDiagnosticsCollector` (already wired for you by `TreeSitterGrammar.parse` — don't call it
     yourself), `Node.cyclomaticComplexity(branchKinds:)`, `Node.referencedTypeNames(in:)`, and
     `TypeReference.relationship(kind:source:)`.
   - Split what remains by responsibility into stateless value types that take their dependencies as
     stored `let`s — `<Lang>TypeDeclarationExtractor`, `<Lang>MemberExtractor`,
     `<Lang>ParameterExtractor`, `<Lang>BaseClassResolver`, `<Lang>TypeReferenceResolver`. Each takes
     only what it needs (`context`, plus any collaborator it depends on) and returns a value — never
     a mutating method on the extractor itself. A method that assembles a `Member` from
     already-resolved pieces takes a `Signature` (the declaration's own syntax — decorators,
     parameters, access level) and a `ResolvedReferences` (the call sites/assignments/field reads the
     caller already computed) rather than a long parameter list, e.g.
     `PythonMemberExtractor.callable(_:signature:references:)`. Anything with no state and no `Node`
     belongs on a value: a method in an `extension` on `Node` or `String`, never a caseless enum of
     `static func`s.

6. **Language identity + quirks** — create `Sources/Acai<Lang>/<Lang>Language.swift` with:
   - `extension CodeArtifact.SourceLanguage { public static let <lang> = .init(rawValue: "<lang>") }`
     — the constant lives in the plugin, never in `AcaiCore` (lowerCamel raw value, e.g. `typeScript`).
   - `extension <Lang>CodeParser { public var configuration: LanguageConfiguration { … } }` listing
     this language's `primitiveTypeNames`, `collectionTypeNames`, any framework `annotationStereotypes`,
     an optional `generatedCodeFilter`, and `excludedDirectories` (build-output/dependency dirs).
     `configuration` is required — there is no empty default; state it explicitly.

7. **Build-system detector (optional)** — if the language has a recognisable project layout, add a
   `BuildSystemDetector` in the plugin (e.g. `Sources/Acai<Lang>/<Lang>Detector.swift`), mirroring
   `FlutterDetector`. A `public init()` is required (it's constructed from another module).

8. **Register in the composition root** — in `Sources/AcaiLibrary/`:
   - add `<Lang>CodeParser()` to `standardParsers` in `AnalysisService+Standard.swift`,
   - add the detector (if any) to `standardDetectors` there,
   - add `@_exported import Acai<Lang>` to `Exports.swift`,
   - add `"Acai<Lang>"` to `AcaiLibrary`'s dependency list in `Package.swift`.
   `AcaiCLI`/`AcaiApp` need no change — they depend on `AcaiLibrary`.

9. **Tests** — add fixtures under `Tests/Acai<Lang>Tests/`, mirroring an existing plugin's layout.
   Then register the parser in the two suites that hold *every* language to the same bar, so your
   plugin joins them for free:
   - `Tests/AcaiLibraryTests/ParserConformanceTests.swift` — add a small fixture to `fixtures` (and
     to `readFixtures` if your language has methods). This checks the producer-contract invariants
     documented on `CodeParser`: `id == qualifiedName`, hierarchical nested ids, simple-name
     receivers, relationship dedup, enrichment idempotence.
   - `Tests/AcaiParserGoldenTests/` — add one broad fixture and record its golden with
     `ACAI_RECORD_PARSER_GOLDENS=1 swift test --filter AcaiParserGoldenTests`. Read the recorded
     JSON once before committing it: it is the thing a later refactor has to reproduce exactly.

10. **Documentation** — add a `Sources/Acai<Lang>/Acai<Lang>.docc/Acai<Lang>.md` catalog page (copy an
   existing plugin's), then **link it from the module map** in
   `Guides.docc/Guides.md` under "Language parsers":
   `- **[Acai<Lang>](/documentation/acai<lang>/)** — <language> (`.ext`, …).`
   The page itself is published automatically (`Scripts/docs_generate.sh` reads the manifest), but
   nothing links to it until you add that line, so this step is what makes it reachable. Also add the
   language to the table in `README.md` under "Supported languages".

Then run `swift build`, `swift test --filter Acai<Lang>Tests`, and `swiftlint lint --strict`.
