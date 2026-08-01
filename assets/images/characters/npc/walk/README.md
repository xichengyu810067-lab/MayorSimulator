# NPC directional walk atlases

Production assets for the map-scale NPC rig in `scripts/world/npc_actor.gd`.

## Runtime contract

- Eight atlases: `resident`, `resident-florist`, `student`, `merchant`,
  `elderly`, `worker`, `civil-servant`, and `council-member`.
- Every `sheet-transparent.png` is 768×768 with 192×192 cells.
- Rows are `down`, `left`, `right`, `up`; columns are four articulated walk
  phases. Left and right are separately authored, not runtime mirrors.
- Frames share a bottom-centre feet anchor. The runtime draws a 64×64 region
  inside a 52×68 hit target and advances frames from real travelled distance.
- `raw-sheet.png` preserves the generated magenta-background source;
  `npc_walk-1.png` through `npc_walk-16.png`, strips, GIF previews, and
  `pipeline-meta.json` are deterministic processing outputs.

## Art direction and prompt contract

Each role was generated from its existing portrait reference while preserving
identity, clothing, palette, hand-painted outline treatment, and the cute,
healing fairy-tale town-simulation style. The common generation contract asks
for a clean HD (non-pixel-art) 4×4 sheet, full-body actors with generous cell
margins, stable feet, real heel-to-toe placement, bent knees, alternating leg
support, opposing arm swing, subtle weight transfer and attached secondary
accessory motion. It explicitly forbids skating, repeated poses, whole-body
squash shortcuts, detached effects, labels, scenery, shadows, grid lines, and
anything crossing a cell boundary. The source background is solid `#FF00FF`
for deterministic chroma removal.

The complete resident prompt is retained in `resident/prompt-used.txt`; the
other roles use that same layout and motion contract with their own portrait
identity and role-specific clothing substituted.

## Deterministic processing and validation

Run from the project root with the bundled workspace Python runtime:

```powershell
python tools/art/despill_npc_walk_atlases.py --root assets/images/characters/npc/walk
python tools/art/validate_npc_walk_atlases.py --root assets/images/characters/npc/walk --report artifacts/logs/npc-walk-atlas-validation.json
```

`resident-florist` uses `tools/art/assemble_npc_walk_atlas.py` to replace its
original clipped up-facing row with the separately generated safe row before
the same despill and validation pass.
