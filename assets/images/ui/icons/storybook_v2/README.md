# Storybook V2 UI Icons

This is the active illustrated icon family for Mayor Simulator. Runtime lookup is centralized in `res://ui/theme/ui_icon_catalog.gd`.

## Delivery

- 36 functional 256×256 RGBA PNG icons.
- 1 neutral 256×256 RGBA fallback icon.
- Original legacy icons remain one directory above and are not deleted.
- Complete ImageGen chroma-key sources for all 37 canonical files are archived at `assets/archives/storybook-v2-ui-icon-sources-20260730-r2.zip`; the original 34-file archive is retained for provenance.
- Build and QA utility: `tools/art/build_storybook_ui_icons.py`.

## Art direction

- Cozy, cute fairy-tale healing city-builder art.
- Premium hand-painted children's storybook finish using soft gouache and watercolor texture.
- Rounded, readable silhouette with a subtle dark-walnut painted edge; never a thick black cartoon outline.
- Upper-left warm light; restrained parchment, walnut, sage, muted teal-blue, dusty coral and honey-gold palette.
- One dominant concept, generally no more than two supporting objects.
- No emoji faces on objects, glossy plastic 3D rendering, corporate vector clip art, text, logos or watermarks.
- No baked background, frame, medallion, ground patch or cast shadow.
- Final visible bounds are optically centered on a 256×256 transparent canvas with at least 12 px edge safety.

The world background and NPC art were used only as palette, brushwork and mood references. The approved `city_hall` output became the visual anchor for the other calls.

## Shared ImageGen prompt

Every canonical asset was generated through its own isolated built-in ImageGen call. Assets that failed the real-size light/dark review received additional isolated regeneration calls; CLI/API fallback was not used.

```text
Use case: stylized-concept
Asset type: production game UI icon for a cozy fairy-tale city builder
Input image: approved city_hall ImageGen output, style reference only
Primary request: [subject brief from the table below]
Style/medium: premium hand-painted children's storybook; soft gouache and watercolor texture; subtle dark-walnut painted edge; rounded elegant silhouette; refined cozy/healing mood; handcrafted rather than glossy plastic or generic mobile-game clip art.
Composition/framing: one centered isolated subject, strong simple silhouette, fills about 84% of the square, even safe padding, readable at 24px, 32px, 44px, 64px and 128px. No frame, badge, medallion, plate, ground patch or scenery.
Lighting/mood: gentle upper-left morning light.
Color palette: parchment cream, warm walnut, sage green, muted teal-blue, dusty coral, restrained honey gold.
Scene/backdrop: perfectly flat solid #ff00ff chroma-key background for local removal.
Constraints: no text, letters, numbers, logos, watermark, emoji face, glossy 3D toy render, corporate vector clip art, thick black outline, cast shadow on the background, floor plane or reflection. Background must be exactly uniform #ff00ff with no gradient, texture, shadow or lighting variation. Do not use #ff00ff inside the subject. Keep the subject fully visible and uncropped.
```

## Subject briefs

| File | Functional meaning | Subject brief |
|---|---|---|
| `city_hall.png` | Municipal center / new game | Compact fairy-tale town hall with short clock tower, warm arched doorway, teal roof, gold pennant and two flower planters. |
| `time.png` | Date / continue | Brass pocket watch with a small sunrise arc and one leaf; no clock numbers. |
| `treasury.png` | Funds / finance | Rounded walnut treasure chest, slightly open with a few coins and a teal civic ribbon. |
| `population.png` | Residents / population | Three restrained storybook villager shoulder portraits: adult woman, adult man and elder. |
| `wellbeing.png` | Satisfaction | Warm coral heart with one new sage leaf; no face. |
| `complaint.png` | Grievance | Cream speech bubble containing a small broken-heart symbol and one coral alert dot; no face. |
| `trust.png` | Civic trust | Two hands in differently colored sleeves shaking in front of a small teal shield. |
| `score.png` | City score | Honey-gold five-point award star embraced by two sage laurel branches; no face. |
| `city_level.png` | City rating | Three progressively taller fairy-tale roofs/towers on stepped levels, topped by a gold pennant. |
| `theme.png` | Light/dark appearance | Gentle sun and crescent moon overlapping beside a small paintbrush; no faces. |
| `settings.png` | Settings | Rounded carved-walnut and teal-enamel gear with a brass floral center. |
| `exit.png` | Leave game | Half-open arched wooden door, warm path beyond and a clear coral outward arrow. |
| `buildings.png` | Building management | Oversized wooden building mallet crossing a short blue blueprint roll with one bold roofline. |
| `governance.png` | Governance / policy | Dominant teal civic lectern with a large gold civic seal, short bill roll and quill. |
| `justice.png` | Court | Balanced gold scales with one walnut gavel; no people or courthouse scene. |
| `oversight.png` | Oversight | Large brass magnifying glass over a teal civic audit ledger with seal and color tabs. |
| `public_affairs.png` | Citizen requests | Warm woven/wooden suggestion box holding a cream letter with a heart seal and a simple speech ribbon. |
| `city_data.png` | City data | Three dominant rounded color bars, one broad rising curve, and a small magnifying glass; no book or numbers. |
| `report.png` | Monthly report | Closed thick teal monthly ledger with a dominant blank calendar grid, wax seal and three side tabs; no numbers. |
| `blueprint.png` | Blueprint design | Unrolled blue building plan with a simple cream-gold house drawing, wooden pencil and brass ruler. |
| `customize.png` | Building appearance | Oversized wooden paintbrush sweeping broad teal, coral and sage strokes beneath one simple roofline. |
| `demolish.png` | Demolition | Walnut-handled gold mallet breaking a short rounded gray stone wall with only a few loose stones. |
| `environment.png` | Environment service | One graceful sage leaf embracing one clear muted teal-blue water droplet with a restrained honey-gold morning glint. |
| `education.png` | Education service | One open parchment fairy-tale book with a warm-walnut pencil and small teal graduation cap; blank pages, no text. |
| `healthcare.png` | Healthcare service | One welcoming cream-stone medical cottage with rounded teal roof, glowing doorway, sage herbal cross and medicinal sprigs. |
| `building_housing.png` | Housing category | One warm fairy-tale cottage with teal rounded roof, lit windows and a small flower box. |
| `building_economy.png` | Economy category | Low market stall dominated by an oversized coral striped awning and large brass gear sign. |
| `building_community.png` | Community services | Open parchment book growing a rounded healing tree with one coral heart-shaped leaf. |
| `building_mobility.png` | Safety and mobility | One rounded teal storybook bus carrying a small understated gold shield. |
| `building_utilities.png` | Utilities category | One warm-stone/copper utility tower combining clear water-drop, lightning and pipe motifs. |
| `building_civic.png` | Civic category | Oversized gold balance scales standing on a low cream-stone civic arch base with a short teal ledge. |
| `blueprint_material.png` | Material parameter | Neat fan of wood plank, red brick and warm-gray stone samples; no tools. |
| `blueprint_size.png` | Scale parameter | Three tightly grouped, matching fairy-tale house forms with an exaggerated small-to-large height progression. |
| `blueprint_floors.png` | Floors parameter | One three-storey fairy-tale tower cutaway with clearly separated warm-window floors. |
| `blueprint_workers.png` | Workforce parameter | One friendly storybook architect/builder with honey hardhat, teal workwear, small wrench and plan roll. |
| `blueprint_decoration.png` | Decoration parameter | One ornate arched window with flower box and a small gold pennant ribbon. |
| `fallback.png` | Missing/unknown icon | Carved walnut signpost with a parchment plaque, one gold question mark and one sage leaf. |

## Rebuild

Use the bundled Python runtime with Pillow and the installed ImageGen chroma-removal helper:

```powershell
& <python.exe> tools/art/build_storybook_ui_icons.py `
  --raw-dir .tmp/icon-redesign-20260730/raw `
  --alpha-dir .tmp/icon-redesign-20260730/alpha `
  --output-dir assets/images/ui/icons/storybook_v2 `
  --evidence-dir artifacts/visual-qa/storybook-v2-icons `
  --chroma-helper $env:CODEX_HOME/skills/.system/imagegen/scripts/remove_chroma_key.py
```

The builder invokes the installed helper with a soft matte and despill for new or changed raw sources, crops by visible alpha, normalizes the maximum subject axis to 224 px, centers the result, verifies magenta removal and edge safety, and writes light/dark plus runtime-size contact sheets. Pass `--force-chroma` when every alpha intermediate must be rebuilt deliberately.
