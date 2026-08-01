# SDK API

Run commands from the project root through `sdk/mayor-sdk.ps1`. The Python entrypoint is `sdk/mayor_sdk.py`.

## Exit codes

| Code | Meaning |
| ---: | --- |
| `0` | Command or delegated gate passed |
| `1` | SDK contract check or delegated gate failed |
| `2` | Invalid arguments, missing required executable/file, or orchestration error |

## `doctor`

Check manifest paths, `project.godot` contracts, assertion registry consistency, skill completeness, CI integration, Python, PowerShell, Pillow, and Godot discovery.

```powershell
& .\sdk\mayor-sdk.ps1 doctor [--json] [--require-godot] [--godot <path>]
```

Missing Pillow is a warning. Missing Godot is a warning unless `--require-godot` is supplied.

## `self-test`

Perform static SDK contract validation without starting the game. CI runs this before downloading Godot.

```powershell
& .\sdk\mayor-sdk.ps1 self-test [--json]
```

## `stack` and `tests`

Print the canonical technical stack or live assertion manifest. Use `--json` for automation.

```powershell
& .\sdk\mayor-sdk.ps1 stack --json
& .\sdk\mayor-sdk.ps1 tests --json
```

## `version`

Inspect version layers independently: Git commit validity, SDK SemVer compatibility, Windows export metadata, the latest update-log date, content versions, and save/data schema versions.

```powershell
& .\sdk\mayor-sdk.ps1 version
& .\sdk\mayor-sdk.ps1 version --json
```

An `absent`, `invalid_or_empty`, or `initialized_unborn` Git result is a warning about traceability, not proof that project files are missing.

## `chats`

Inventory Codex JSONL sessions whose metadata `cwd` matches this project. Raw conversation text is classified in memory and is not retained or emitted.

```powershell
& .\sdk\mayor-sdk.ps1 chats --since-days 7 --json
& .\sdk\mayor-sdk.ps1 chats --write-reference
```

Use `--write-reference` only after reviewing recent chats semantically. It atomically regenerates `references/chat-derived-workflows.md`; it does not update curated completion claims in `recent-chat-contracts.md`.

## `install-skill`

Synchronize the canonical `skills/mayor-simulator-sdk` source into the project-local `.codex/skills` installation. It copies canonical files without deleting unrelated files.

```powershell
& .\sdk\mayor-sdk.ps1 install-skill
```

Run `doctor` afterward; `installed skill` must report `matches canonical source`.

## `verify`

Delegate to `tools/run_assertion_matrix.ps1` with isolated app-data and logs.

```powershell
& .\sdk\mayor-sdk.ps1 verify [--godot <path>] [--output-root <fresh-path>]
```

If `--output-root` is omitted, the SDK selects a UTC-stamped path under `.tmp/sdk/assertion-matrix`.

## `ui-qa`

Delegate to the visible screenshot acceptance runner. This opens a Godot window.

```powershell
& .\sdk\mayor-sdk.ps1 ui-qa [--godot <path>] [--output-root <fresh-path>]
```

## `save-qa`

Delegate to the Windows process-kill save durability runner.

```powershell
& .\sdk\mayor-sdk.ps1 save-qa [--godot <path>] [--output-root <fresh-path>]
```

## `build`

Delegate to `tools/write_release_evidence.ps1`. All paths must be fresh and the template archive must match Godot 4.7.

```powershell
& .\sdk\mayor-sdk.ps1 build `
  --version <YYYY.MM.DD> `
  --godot <console-exe> `
  --templates <export-templates.tpz> `
  --export-appdata <fresh-external-path> `
  --output-root <fresh-project-path>
```

The build command does not weaken or replace the existing release runner's path, hash, staging, smoke, legal-file, or evidence checks.

## Direct chat inventory utility

Scan all project-root Codex JSONL sessions without retaining or printing raw chat text:

```powershell
python sdk/chat_inventory.py `
  --sessions-root 'C:\Users\USER\.codex\sessions' `
  --project-root 'C:\Users\USER\遊戲' `
  --format json
```

Treat error counts as text-signature occurrences in tool outputs, not unique defects.
