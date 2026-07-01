export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null
git config --global safe.bareRepository all || true
swift build -c debug --target UMLCSharpTests
