---
name: mayor-simulator-sdk
description: Maintain, inspect, test, visually verify, and build the Godot 4.7 Mayor Simulator project through its canonical SDK and evidence gates. Use when Codex works in this project on technical-stack or version discovery, recent-chat maintenance, GDScript or JSON changes, test selection, isolated Godot runs, transportation topology, NPC navigation, localization, visible UI acceptance, save durability, release packaging, CI, recurring project errors, or SDK automation.
---

# Mayor Simulator SDK

Use the project SDK as the stable entrypoint. Keep runtime behavior in Godot/GDScript and delegate existing QA and release judgments to their canonical PowerShell runners.

## Route the task

1. Run the project SDK's `doctor` before changing tooling, tests, CI, exports, or dependencies. Use the bundled wrapper below when this skill is outside the embedded SDK project root.
2. Read only the reference needed for the request:
   - Read [references/stack.md](references/stack.md) for languages, runtimes, dependencies, and scope boundaries.
   - Read [references/api.md](references/api.md) for CLI commands, arguments, outputs, and exit codes.
   - Read [references/examples.md](references/examples.md) for the high-frequency workflows derived from project chats.
   - Read [references/troubleshooting.md](references/troubleshooting.md) after any known Godot, path, localization, evidence, or export failure.
   - Read [references/chat-derived-workflows.md](references/chat-derived-workflows.md) when prioritizing automation or auditing chat coverage.
   - Read [references/recent-chat-contracts.md](references/recent-chat-contracts.md) before changing transportation, NPC locomotion, policy ordering, chart localization, evidence tooling, or feature-freeze scope.
   - Read [references/versioning.md](references/versioning.md) for Git, release tags, content versions, save schemas, or migrations.
3. Discover live tests through `mayor-sdk.ps1 tests`; never write a passed-test count from inventory output into new code or documentation.
4. Choose the smallest authoritative gate that proves the claim.
5. Use a new output root for every QA or release run. Preserve failed logs and never rename them into success evidence.
6. Report what was actually run, the exit code, evidence path, and any intentionally untreated issue.

## Preserve project contracts

- Keep the gameplay feature freeze for unrelated work. A later explicit user request authorizes only the named feature scope; it does not silently thaw the whole project.
- Keep the lower-council module isolated under its existing lower-council paths until integration is explicitly requested.
- Keep `tests/assertion_matrix.json` as the canonical automated test inventory.
- Set isolated `APPDATA`, `LOCALAPPDATA`, and a writable `--log-file` through the existing runners.
- Require visible GUI traversal and screenshots for UI, localization, interaction, animation, or art claims. Headless success is supplementary.
- Derive catalog expectations from registries or manifests; do not introduce magic counts.
- Treat release evidence as a single-run chain. Old tests, staging, logs, or summaries cannot be combined into a new pass.
- Do not add C#, GDExtension, Node.js, a database, a backend, or another runtime dependency unless the user explicitly changes the architecture.

## Use the SDK

Invoke through the project wrapper:

```powershell
& .\sdk\mayor-sdk.ps1 doctor
& .\sdk\mayor-sdk.ps1 stack
& .\sdk\mayor-sdk.ps1 version
& .\sdk\mayor-sdk.ps1 tests
& .\sdk\mayor-sdk.ps1 chats --since-days 7 --json
& .\sdk\mayor-sdk.ps1 verify --godot 'C:\path\to\Godot_v4.7-stable_win64_console.exe'
```

Alternatively run [scripts/invoke-sdk.ps1](scripts/invoke-sdk.ps1) from this skill. It sets `MAYOR_PROJECT_ROOT` only for its child invocation and restores the caller environment afterward. Set `MAYOR_SDK_HOME` only in the calling process to use a standalone SDK root; otherwise it falls back to this project's embedded `sdk`. Use `ui-qa` for visible traversal, `save-qa` for Windows process-kill durability, and `build` only with fresh release paths and matching export templates.

## Validate SDK changes

Run all three checks after changing the SDK, skill, manifest, CI gate, or SDK tests:

```powershell
python sdk/mayor_sdk.py self-test
python -m unittest discover -s tests/sdk -p 'test_*.py'
python C:\Users\USER\.codex\skills\.system\skill-creator\scripts\quick_validate.py skills\mayor-simulator-sdk
& .\sdk\mayor-sdk.ps1 install-skill
& .\sdk\mayor-sdk.ps1 doctor
```

Then run the relevant Godot gate when the change can affect the game, evidence, export, or runner behavior.
