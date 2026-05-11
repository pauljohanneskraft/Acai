<img src="Sources/UMLApp/Resources/Assets.xcassets/AppIcon.imageset/Icon-macOS-Default-1024x1024%401x.png" height="150" align="right">

# UML — See Your Codebase

**Point UML at a folder of source code and get a UML class diagram back.** It works across Swift, Kotlin, Java, TypeScript/JavaScript, and Dart — no annotations, no project files, no setup. Use the native macOS app to explore visually, or the `uml` CLI to wire it into your build.

[![Swift 6](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/platform-macOS%2015+-blue.svg)](https://www.apple.com/macos/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## Why UML?

- 🌍 **Multi-language out of the box** — one tool for polyglot repos, not five.
- ⚡️ **Zero configuration** — point it at a directory and go.
- 🎨 **Tweak what you see** — filter members, methods, access levels, group by file or namespace, pick a theme.
- 🤖 **Automatable** — first-class CLI for CI, docs pipelines, and pre-commit hooks.
- 📦 **Standard output** — emits DOT/Graphviz, so you can render anywhere.

---

## Try it in 60 seconds

```sh
git clone https://github.com/pauljohanneskraft/UML.git
cd UML
./Scripts/cli_create.sh && ./Scripts/cli_install.sh

# Diagram any codebase you have lying around:
uml diagram --source ~/path/to/your/project --output project.dot

# Render to PNG (requires Graphviz: `brew install graphviz`):
dot -Tpng project.dot -o project.png && open project.png
```

Prefer a UI? Build and install the macOS app:

```sh
./Scripts/app_create.sh && ./Scripts/app_install.sh
open -a UML
```

---

## Supported languages

| Language               | Parser        |
| ---------------------- | ------------- |
| Swift                  | SwiftSyntax   |
| Kotlin                 | Tree-sitter   |
| Java                   | Tree-sitter   |
| TypeScript / JavaScript| Tree-sitter   |
| Dart                   | Tree-sitter   |

Mix and match — UML produces one unified model across all of them.

---

## What's in the box

- **UML.app** — A SwiftUI macOS app for browsing projects, fine-tuning what's shown, and exporting DOT.
- **`uml` CLI** — Analyze, store, list, and diagram from the command line. Run `uml --help` for the full menu.
- **Swift libraries** — Reusable packages for parsing, modeling, and DOT generation. Bring them into your own tools.

### CLI cheat sheet

```sh
uml analyze ./MyProject --output model.json         # Parse code → JSON model
uml store myproj ./MyProject                        # Analyze and stash under a name
uml list                                            # Show stored analyses
uml diagram --from myproj --theme dark --group-by namespace
uml diagram --source ./MyProject --language kotlin --language java
```

Pair `--config myconfig.yaml` with any `diagram` invocation to lock down options for repeatable output.

---

## Requirements

- **Swift 6** toolchain
- **macOS 15+** for the app (libraries and CLI run on broader Apple platforms)
- **Graphviz** (optional) — for rendering DOT into PNG/SVG: `brew install graphviz`

---

## Build from source

```sh
swift build        # Build everything
swift test         # Run the test suite
```

Install or remove binaries with the helper scripts:

```sh
./Scripts/cli_create.sh      # Produces `uml` in .build/artifacts
./Scripts/cli_install.sh     # Installs to your binary directory
./Scripts/cli_uninstall.sh   # Removes the installed binary

./Scripts/app_create.sh      # Produces UML.app in .build/artifacts
./Scripts/app_install.sh     # Installs to /Applications/UML.app
./Scripts/app_uninstall.sh   # Removes /Applications/UML.app
```

---

## Contributing

Issues and pull requests are welcome. If you're adding support for a new language, the existing Tree-sitter integrations under `Sources/UMLKotlin`, `Sources/UMLJava`, etc. are a good starting point.

## License

[MIT](LICENSE) © Paul Johannes Kraft
