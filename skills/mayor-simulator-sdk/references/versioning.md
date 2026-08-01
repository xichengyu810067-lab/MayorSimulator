# Versioning and migration reference

Use `& .\sdk\mayor-sdk.ps1 version --json` as the live inventory. Do not merge these layers in prose:

| Layer | Current source | Contract |
| --- | --- | --- |
| Git identity | `.git` | Valid only when Git can resolve a repository/worktree and commit; an empty directory is not version control |
| SDK compatibility | `sdk/manifest.json`, `.mayor-sdk.json` | SDK uses SemVer; the game declares an accepted range and intended integration path |
| SDK pin | `.gitmodules`, parent gitlink | A submodule is established only after the SDK has its own commit and the parent records that commit |
| Release tag | `.github/workflows/godot-ci.yml` | `vYYYY.MM.DD` for tag-triggered releases |
| Windows metadata | `export_presets.cfg` | `YYYY.M.D.0`; file and product versions must agree |
| Update log | `data/version_updates.json` | Human-facing development version and date |
| Content compatibility | `game_session.gd`, `save_envelope.gd` | Both must agree on the current content identifier |
| Save/data schemas | save envelope, city state, population, NPC record | Independent integer versions and supported ceilings |

## Change a release version

1. Run `mayor-sdk version --json` and preserve the before-state.
2. Update every release source required by the existing CI contract in one change.
3. Do not change content or save schema merely because the release date changes.
4. Run SDK self-test, SDK unit tests, and the release metadata gate.
5. A local workflow file is not proof of a remote GitHub Actions run.

## Change a schema

1. Define the new schema ceiling and the minimum supported source version.
2. Add an explicit migration or explicit rejection path; never silently coerce unknown future data.
3. Test the oldest supported payload, every migration edge, current round-trip, malformed input, and unknown future versions.
4. Run OS-kill durability when the serialized save topology changes.
5. Keep schema versions separate from marketing/release versions.

## Traceability gate

The project has CI and release-evidence definitions. Do not claim version-control closure until the current tree proves a game commit, an independent SDK commit, the parent gitlink, configured remotes, and successful pushes. A workflow file still cannot prove a remote GitHub Actions run. Initializing or publishing Git changes external project state and requires an explicit user request.
