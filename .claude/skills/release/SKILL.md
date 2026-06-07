---
name: release
description: Build and/or install the release CLI (uml) and the macOS app via the Scripts/ helpers. Use when the user wants a release build, to install the uml CLI locally, or to produce the .app bundle.
disable-model-invocation: true
---

# Release build / install

Release artifacts are built `-c release --arch arm64` by the scripts in `Scripts/` — not by plain `swift build`. The app scripts use macOS-only tools (`sips`, `iconutil`) so they run on macOS only.

Before building, confirm the working tree is in the state the user wants released, and that `swiftlint lint --strict` and `swift test --parallel` pass.

Run only what the user asked for:

- Build CLI binary: `./Scripts/cli_create.sh`
- Install `uml` to the user's bin dir: `./Scripts/cli_install.sh`
- Build the `.app` bundle: `./Scripts/app_create.sh`
- Install the app: `./Scripts/app_install.sh`
- Uninstall: `./Scripts/cli_uninstall.sh` / `./Scripts/app_uninstall.sh`

`$ARGUMENTS` may name which target ("cli" / "app") and action ("create" / "install"); if unspecified, ask. Report the resulting artifact path(s) from the script output.
