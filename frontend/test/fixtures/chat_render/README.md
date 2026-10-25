# CP-07 Chat render resources

`render_resources.dart` is a checkpoint-only font loader shared by the seven
Chat render suites. It resolves the active `flutter` package from the existing
`.dart_tool/package_config.json` to locate
that SDK's `bin/cache/artifacts/material_fonts/` directory. No machine-specific
path, download, or dependency change is required. Missing resources
fail setup instead of silently producing placeholder evidence.

Resources used, inspected with Flutter 3.22.0 / Dart 3.4.0:

- `roboto-regular.ttf`, `roboto-medium.ttf`, `roboto-bold.ttf`, and
  `roboto-italic.ttf`: the existing SDK's Roboto family, loaded as `Roboto`, the
  existing render harness's Material text family. These files cover regular,
  medium, bold, and italic text without changing the theme or production code.
  License supplied by the SDK: `material_fonts/roboto_license.txt` (Apache 2.0).
- `materialicons-regular.otf`: the existing SDK's Material Icons font, loaded as
  `MaterialIcons` for the real `Icons.*` codepoints. License supplied by the SDK:
  `material_fonts/materialicons_license.txt` (Creative Commons Attribution 4.0).
- `WorkSans-Regular.ttf`: one unmodified font copied from the existing local
  Pub cache, package `flutter_gallery_assets` 1.0.2,
  `lib/fonts/google_fonts/WorkSans-Regular.ttf`. Its embedded copyright is
  Copyright 2019 The Work Sans Project Authors
  (https://github.com/weiweihuanghuang/Work-Sans); embedded licensing specifies
  SIL Open Font License 1.1. `WorkSans-OFL.txt` combines that embedded copyright
  with the standard OFL 1.1 text already supplied in that package's
  `lib/fonts/rubik/OFL.txt`. No network download or package installation.
  It is loaded as `ChatRenderSymbols` only by loading/recovery, with an explicit
  text-theme fallback for the production Retry label's U+2192 right arrow,
  which the SDK Roboto cmap lacks. Roboto remains the primary text family.
- Food photo: existing `frontend/assets/images/nutrition.jpg`, referenced as
  `assets/images/nutrition.jpg` from the frontend test working directory. It was
  already the intended image in the old macOS absolute path. Repository origin:
  commit `c84ee4078d91faae5acefa8f7bf2bef3ae7321bb` (project baseline).
  SHA-256: `33f576d3fdc122a8f86f12fec779fffd80a717e47011f7e6725f0ccc086c4ad8`.
  Visual inspection found only food, with no people or personal data. No separate
  image license/attribution was found in the repository; no copy or new rights
  claim is made. This is a render fixture, not proof of the seeded meal's
  identity or nutritional values.

`flutter test` uses Ahem and disables automatic asset-font loading. The explicit
FontLoader calls restore readable text and Material icons for evidence. Food
tests cache the actual local FileImage before pumpWidget, so decoding cannot
race screenshot creation. Existing scenarios, viewport, primary theme, and
assertions remain unchanged; only the missing-glyph fallback is added. PNG
output remains outside the repository through
`SAMAN_RENDER_EVIDENCE` (system temporary directory by default).

These screenshots document the current Flutter UI. They are not design
references, and readable SDK Roboto does not establish design typography parity
with the approved Chat references.
