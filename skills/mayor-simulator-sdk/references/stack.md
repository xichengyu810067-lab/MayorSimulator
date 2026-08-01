# Technical stack

`sdk/manifest.json` is the machine-readable source of truth. Run `& .\sdk\mayor-sdk.ps1 stack --json` before making a dependency or architecture claim.

## Runtime

| Layer | Technology | Current contract |
| --- | --- | --- |
| Engine | Godot Standard | `4.7.stable`, feature tag `4.7` |
| Language | GDScript | Godot 4.x; gameplay, UI, systems, tests, and Godot tools |
| Scene/data | `.tscn`, `.tres`, `.gd`, `.json` | Main scene `res://scenes/Main.tscn`; JSON catalogs, localization, manifests, saves, and evidence |
| Localization | `L10n` Autoload | `res://scripts/app/localization_service.gd`; five locales |
| Rendering | Compatibility renderer | `gl_compatibility`, `canvas_item` shaders, 1280×720 logical viewport |
| Assets | PNG, GIF, WAV, SVG | Godot import sidecars stay with their source assets |

Normal game runtime does not require Python, PowerShell, Node.js, C#, GDExtension, a native DLL, a database, a backend, an API key, or a package manager.

## Development and build

| Tool | Purpose | Requirement |
| --- | --- | --- |
| PowerShell 7.4+ | Assertion orchestration, isolated app-data, OS-kill QA, screenshots, hashing, packaging, evidence | Required for the full Windows/release workflow |
| Python 3.10+ | SDK CLI and deterministic asset tooling | Required for SDK automation |
| Pillow | Sprite atlas, PNG and UI icon tools | Optional unless running `tools/art/*.py` |
| Godot 4.7 Export Templates | Windows/Linux source exports | Required only for export/release workflows; must match engine version |
| GitHub Actions | Windows assertion/export smoke and Ubuntu export/Linux smoke | Workflow defined; a local file is not proof of a remote successful run |
| Bash/coreutils | `curl`, `unzip`, `sha256sum`, `timeout`, `grep`, `tar` behavior in Ubuntu CI | CI-supplied, not a Windows runtime dependency |

## Testing architecture

- Custom `SceneTree` test scripts; no GUT, WAT, pytest, or Node test framework is required.
- `tests/assertion_matrix.json` is the canonical test registry.
- `tools/run_assertion_matrix.ps1` isolates each case and checks exit code, success marker, diagnostics, ObjectDB leaks, and resource leaks.
- `tools/run_ui_capture_acceptance.ps1` performs visible 2880×1800 traversal plus screenshot and source-fingerprint checks.
- `tools/run_save_os_kill_qa.ps1` validates Windows process-kill recovery across real save phases.
- `tools/write_release_evidence.ps1` is the authoritative one-run release acceptance entrypoint.

## Version layers

- The SDK uses Semantic Versioning and the game declares an accepted SDK range in `.mayor-sdk.json`.
- The intended integration is a pinned `sdk/` Git submodule; the submodule claim is valid only after both repositories have commits and the parent records a gitlink.
- Windows export metadata uses a date-derived four-part version such as `2026.7.31.0`.
- CI accepts release inputs or tags in `YYYY.MM.DD` form and expects a `v` prefix for tags.
- Game content currently has its own `vertical_slice_1` identifier.
- Save envelope, city state, population, and NPC records have separate schema ceilings.
- These layers are intentionally reported separately by `mayor-sdk version`; release, content, and schema versions are not one interchangeable number.

## Scope boundaries

- Retain the current feature freeze until the user changes it.
- Keep lower-council work isolated unless integration is explicitly requested.
- Do not present generated images, local staging, headless checks, or old reports as public-release evidence.
