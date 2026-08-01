# Recent chat contracts

Review date: 2026-08-01 Asia/Taipei.

This file records semantically reviewed conclusions from recent project root chats. It distinguishes completed evidence, observed gaps, and requirements still being implemented. Do not upgrade an in-progress requirement to a completed capability without reading the newer chat turn and rerunning its gate.

## Completed and reusable

### Release and evidence

- Keep 1280x720 inside the strict multi-resolution geometry and operability matrix; a fullscreen desktop screenshot is not 1280x720 window proof.
- Require scroll range plus actual scroll movement and reachable/clickable controls, not only non-overflow geometry.
- Keep screenshot capture append-only and run-scoped. Verify expected filenames, PNG dimensions, bytes, hashes, logs, source fingerprints, exit code, and process cleanup before publishing a summary.
- Keep release acceptance single-run across assertion matrix, five OS-kill phases, import, Windows/Linux exports, Windows smoke, staging, packaging, and source fingerprint comparison.
- Do not use arbitrary caller-supplied exit codes or old artifacts as current evidence.

### NPC locomotion and authority

- Visible NPCs are proxies for authoritative population records; load and population changes must refresh proxies without inventing residents.
- Use foot anchoring for draw position, hitbox, navigation, and depth sorting.
- Advance walk frames from actual traveled distance. A blocked or stopped NPC must not keep stepping, disappear, or teleport to a fallback line.
- Replan around terrain, buildings, and construction changes; include no-corner-cutting, long-run movement, dispersion, and click interaction in acceptance.
- Validate sprite atlases deterministically for frame boundaries, transparent cleanup, directional differences, and common foot baselines before integration.

### UI state and localization

- Policy and bill pages keep separation-of-powers dashboards outside their list and prioritize implemented, review, then unimplemented states.
- Reopening a dynamic tab must localize its title again under the current locale.
- Localized formatted strings must preserve placeholder signatures. Runtime format errors invalidate an apparent green localization pass.
- Long chart pages may scroll; distinguish valid off-screen content from clipping, and visually inspect generated screenshots.

## Observed current gaps

- A concurrent version-governance chat began initializing the game repository and an SDK submodule after the initial audit found an empty `.git`. Treat its state as changing until that chat publishes final commit, gitlink, remote, and push evidence; rerun `mayor-sdk version` before every claim.
- SDK SemVer, release version, update-log version, content version, and save/data schemas are separate sources. Use `mayor-sdk version` to expose drift; do not collapse them into one version.
- Python may be absent from `PATH` even when the Codex bundled runtime or a local installation exists. Use the project wrapper's ordered discovery and preserve access-denied diagnostics.

## Requirement in progress: transport topology

The active transportation chat clarified the product contract but had not published a final completed result when this reference was updated:

- The player chooses station/stop locations and constructs compatible road or rail edges.
- Crossings and related infrastructure belong to the built network, not random background decoration.
- A route becomes active only when its topology is connected and its endpoint/mode constraints are valid.
- Trains, metro vehicles, buses, cars, and motorcycles move only on their compatible active network.
- Service and ticket revenue derive from actual valid routes and service, not station count alone.

Before accepting transport work, read the latest chat, inspect live source, discover current tests through the SDK, and require topology, invalid-network, persistence, economic, and visible traversal evidence.
