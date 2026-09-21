# ``AcaiPython``

The Python plugin — parses `.py` source into the [AcaiCore](/documentation/acaicore/) model with
Tree-sitter.

## Overview

`AcaiPython` is a self-contained language plugin built on Tree-sitter (shared helpers come from
[AcaiTreeSitter](/documentation/acaitreesitter/)). The ``PythonCodeParser`` reports
`SourceLanguage.python` and carries Python's
[LanguageConfiguration](/documentation/acaicore/languageconfiguration); the ``PythonDetector``
finds source via `pyproject.toml` / `setup.py`.

A couple of Python specifics worth knowing: member **types come from type hints** (untyped
attributes are still captured, just without a type), instance attributes are discovered from
`self.x = …` assignments in `__init__`, and `ABC` subclasses count as abstract types for
package-abstractness metrics.

A method decorated `@override`, `@typing.override` or `@typing_extensions.override` carries the
`.override` modifier, so the dead-code scan exempts it like it does for every other language's
override keyword. This is a known, inherent gap: a method that overrides a base-class member
without the decorator (Python has no `override` keyword) carries no such signal and can still be
misreported as dead. Deliberately not papered over with a name-matching heuristic, which would
misclassify same-named, unrelated methods across sibling types.

## Topics

### Parsing

- ``PythonCodeParser``

### Project discovery

- ``PythonDetector``
