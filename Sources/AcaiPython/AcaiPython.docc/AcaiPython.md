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

## Topics

### Parsing

- ``PythonCodeParser``

### Project discovery

- ``PythonDetector``
