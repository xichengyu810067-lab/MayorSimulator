# High-frequency examples

## Start every engineering pass

```powershell
& .\sdk\mayor-sdk.ps1 doctor
& .\sdk\mayor-sdk.ps1 version
& .\sdk\mayor-sdk.ps1 tests
```

Use the doctor result to distinguish missing local tools from source defects. Use the live test list instead of a remembered count.

## Refresh maintenance knowledge from chats

```powershell
& .\sdk\mayor-sdk.ps1 chats --since-days 7 --json
& .\sdk\mayor-sdk.ps1 chats --write-reference
& .\sdk\mayor-sdk.ps1 install-skill
```

First review the recent root chats with Codex thread tools. Use the inventory to measure coverage and repeated diagnostics; do not infer completion from keyword counts.

## Validate a GDScript, JSON, system, or data change

```powershell
& .\sdk\mayor-sdk.ps1 verify `
  --godot 'C:\Users\USER\Tools\Godot\Godot_v4.7-stable_win64_console.exe'
```

Inspect the generated `summary.json` and per-case logs. Do not substitute `--check-only` for the assertion matrix.

## Validate UI, UX, art, localization, animation, or interaction

```powershell
& .\sdk\mayor-sdk.ps1 verify --godot $GodotConsole
& .\sdk\mayor-sdk.ps1 ui-qa --godot $GodotConsole
```

Then manually inspect relevant screenshots and perform any user-required real click traversal. A headless pass cannot close a visual claim.

## Add or repair a building catalog entry

1. Compare `data/catalogs/buildings.gd`, `data/catalogs/content_registry.gd`, `data/catalogs/building_visuals.gd`, and the active draw/render branch.
2. Update the registry, visual mapping, draw branch, localization keys, and affected tests together.
3. Run `tests` to discover the live building/visual contracts.
4. Run `verify`, then `ui-qa` if appearance or placement changed.
5. Report full-catalog parity, not only the named additions.

## Change dynamic localized text

1. Add a stable localization key and a localized template.
2. Translate variable labels before formatting.
3. Avoid substring replacement on an already formatted sentence.
4. Run the assertion matrix and traverse every affected page in every required locale.
5. For `%`-formatted strings, verify placeholder count and type in every locale and reject runtime formatting diagnostics even when the top-level test exits zero.

## Change NPC locomotion or navigation

1. Keep the authoritative population records separate from visible NPC proxies.
2. Anchor rendering, hitboxes, depth, and navigation at the feet.
3. Advance walk animation from actual traveled distance; a blocked NPC must stop stepping.
4. Rebuild paths when construction, demolition, load, or population authority changes.
5. Test static terrain, dynamic obstacles, no-corner-cutting, no teleport fallback, long-run dispersion, NPC click interaction, and visible motion separately.

## Build a player-directed transport network

1. Treat stations, stops, roads, rails, crossings, routes, vehicles, service levels, and revenue as separate domain layers.
2. Require player decisions and placement before creating network edges.
3. Validate connectivity and compatible endpoints before activating a route.
4. Spawn and move vehicles only on an active valid route; never use ambient tile animation as transport-system proof.
5. Derive revenue and service outcomes from actual valid service, not only the number of station buildings.
6. Until the active transport chat publishes a completed test result, treat these as requirements rather than verified implementation.

## Diagnose save or persistence behavior

```powershell
& .\sdk\mayor-sdk.ps1 verify --godot $GodotConsole
& .\sdk\mayor-sdk.ps1 save-qa --godot $GodotConsole
```

Keep every run in a fresh directory. The Windows process-kill result does not prove unplugged-power, disk-cache, filesystem-corruption, or Linux `SIGKILL` behavior.

## Prepare release evidence

```powershell
& .\sdk\mayor-sdk.ps1 build `
  --version '2026.07.31' `
  --godot $GodotConsole `
  --templates 'C:\path\Godot_v4.7-stable_export_templates.tpz' `
  --export-appdata 'C:\tmp\mayor-release-appdata-unique' `
  --output-root '.\.tmp\release-acceptance\unique'
```

Do not reuse either output root. Do not combine a previous matrix, old staging, or an external log with a new evidence claim.

## Update the SDK or this skill

```powershell
python sdk/mayor_sdk.py self-test
python -m unittest discover -s tests/sdk -p 'test_*.py'
python C:\Users\USER\.codex\skills\.system\skill-creator\scripts\quick_validate.py skills\mayor-simulator-sdk
& .\sdk\mayor-sdk.ps1 install-skill
& .\sdk\mayor-sdk.ps1 doctor
```

Update `sdk/manifest.json` first when the stack or canonical entrypoints change, then update only the affected reference page.
