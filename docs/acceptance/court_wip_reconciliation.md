# Court WIP reconciliation ledger

## Decision and provenance

**DECISION=ALREADY_INTEGRATED_NEEDS_LEDGER_CLOSE.** Source branch label:
`agent/realistic-courtroom-flow@65ceea3`. `65ceea3` is the source-label commit,
**not** a commit that itself contains the court WIP. The RAR dirty tree was
materialized as baseline `682b0d1`; current is `e443aeb`.

This is a core-side ledger closure. `20_requirements/WIP_IMPORT_REGISTER` still
needs the controller's separate append-only authority closure; this document
does not edit or rewrite it.

## Exact ownership partition

`git diff --name-only 65ceea3 682b0d1` is 120 paths. These exact 27 are
court-owned: assets 9, localization 6, system 2, UI 3, tests 6, docs 1.

```text
assets/images/ui/courtroom_v1/README.md
assets/images/ui/courtroom_v1/court_clerk.png
assets/images/ui/courtroom_v1/court_clerk.png.import
assets/images/ui/courtroom_v1/courtroom_interior.png
assets/images/ui/courtroom_v1/courtroom_interior.png.import
assets/images/ui/courtroom_v1/defense_table.png
assets/images/ui/courtroom_v1/defense_table.png.import
assets/images/ui/courtroom_v1/judicial_panel.png
assets/images/ui/courtroom_v1/judicial_panel.png.import
data/localization/en.json
data/localization/ja.json
data/localization/ko.json
data/localization/manifest.json
data/localization/zh_CN.json
data/localization/zh_TW.json
scripts/systems/governance/governance_system.gd
systems/governance/justice-oversight/justice_oversight_system.gd
ui/governance/courtroom_stage.gd
ui/governance/courtroom_stage.gd.uid
ui/governance/justice_oversight_panel.gd
tests/assertion_matrix.json
tests/ui/capture_ui_readability.gd
tests/ui/courtroom_visual_acceptance_test.gd
tests/ui/courtroom_visual_acceptance_test.gd.uid
tests/ui/justice_oversight_multi_case_test.gd
tests/unit/governance/justice_oversight_self_test.gd
docs/systems/governance/justice_oversight.md
```

The following literal 93 paths are excluded (complete machine-readable exact
list; no glob is being used):

```text
.gitattributes
.gitignore
.tmp/.gdignore
artifacts/.gdignore
assets/archives/MayorSimulator_BackgroundReference_Pack.zip
assets/archives/building-blueprint-ui-icon-sources.zip
assets/archives/municipal-justice-oversight-v2-sources.zip
assets/archives/picture-first-ui-icon-sources.zip
assets/archives/storybook-v2-ui-icon-sources-20260730-r2.zip
assets/archives/storybook-v2-ui-icon-sources-20260730.zip
assets/images/characters/npc/walk/civil-servant/pipeline-meta.json
assets/images/characters/npc/walk/council-member/pipeline-meta.json
assets/images/characters/npc/walk/elderly/pipeline-meta.json
assets/images/characters/npc/walk/merchant/pipeline-meta.json
assets/images/characters/npc/walk/resident-florist-source/pipeline-meta.json
assets/images/characters/npc/walk/resident-florist-up/pipeline-meta.json
assets/images/characters/npc/walk/resident-florist/pipeline-meta.json
assets/images/characters/npc/walk/resident/pipeline-meta.json
assets/images/characters/npc/walk/resident/prompt-used.txt
assets/images/characters/npc/walk/student/pipeline-meta.json
assets/images/characters/npc/walk/worker/pipeline-meta.json
assets/images/world/buildings/storybook_v1/airport/pipeline-meta.json
assets/images/world/buildings/storybook_v1/bus_station/pipeline-meta.json
assets/images/world/buildings/storybook_v1/city_hall/pipeline-meta.json
assets/images/world/buildings/storybook_v1/court/pipeline-meta.json
assets/images/world/buildings/storybook_v1/factory/pipeline-meta.json
assets/images/world/buildings/storybook_v1/fire_station/pipeline-meta.json
assets/images/world/buildings/storybook_v1/gas_station/pipeline-meta.json
assets/images/world/buildings/storybook_v1/gas_works/pipeline-meta.json
assets/images/world/buildings/storybook_v1/hospital/pipeline-meta.json
assets/images/world/buildings/storybook_v1/library/pipeline-meta.json
assets/images/world/buildings/storybook_v1/mall/pipeline-meta.json
assets/images/world/buildings/storybook_v1/metro_station/pipeline-meta.json
assets/images/world/buildings/storybook_v1/nuclear_power_plant/pipeline-meta.json
assets/images/world/buildings/storybook_v1/oversight_office/pipeline-meta.json
assets/images/world/buildings/storybook_v1/park/pipeline-meta.json
assets/images/world/buildings/storybook_v1/parking_lot/pipeline-meta.json
assets/images/world/buildings/storybook_v1/police_station/pipeline-meta.json
assets/images/world/buildings/storybook_v1/power_plant/pipeline-meta.json
assets/images/world/buildings/storybook_v1/residence/pipeline-meta.json
assets/images/world/buildings/storybook_v1/residence/prompt-used.txt
assets/images/world/buildings/storybook_v1/school/pipeline-meta.json
assets/images/world/buildings/storybook_v1/shop/pipeline-meta.json
assets/images/world/buildings/storybook_v1/social_housing/pipeline-meta.json
assets/images/world/buildings/storybook_v1/stadium/pipeline-meta.json
assets/images/world/buildings/storybook_v1/swimming_pool/pipeline-meta.json
assets/images/world/buildings/storybook_v1/waste_center/pipeline-meta.json
assets/images/world/buildings/storybook_v1/water_works/pipeline-meta.json
backups/.gdignore
builds/.gdignore
docs/development/deferred_todos.md
docs/development/godot_reference.md
docs/development/plugin_reference.md
docs/marketing/BRAND_NAME_AND_PROMOTION_COLLISION_AUDIT_2026-08-03.md
docs/marketing/ENGLISH_TITLE_RENAME_ROUND_1_2026-08-03.md
docs/marketing/EXTERNAL_TITLE_NAMING_PROPOSAL.md
docs/marketing/MVP_ALPHA_PROMOTION_MASTERPLAN_DRAFT_2026-08-03.md
docs/marketing/campaign-01/CAMPAIGN_01_LAUNCH_KIT.md
docs/marketing/campaign-01/ITCH_FIRST_DISTRIBUTION_FUNNEL.md
docs/marketing/campaign-01/VISUAL_ASSET_MANIFEST.md
docs/marketing/campaign-01/prepare_visual_derivatives.py
docs/marketing/campaign-01/visuals/civictale-community-textfree-portrait-v2.png
docs/marketing/campaign-01/visuals/civictale-community-textfree-portrait-v2.png.import
docs/marketing/campaign-01/visuals/civictale-hero-textfree-16x9-v2.png
docs/marketing/campaign-01/visuals/civictale-hero-textfree-16x9-v2.png.import
docs/marketing/campaign-01/visuals/civictale-promise-textfree-9x16-v2.png
docs/marketing/campaign-01/visuals/civictale-promise-textfree-9x16-v2.png.import
docs/marketing/campaign-01/visuals/mayor-simulator-community-1080x1350-v1.jpg
docs/marketing/campaign-01/visuals/mayor-simulator-community-1080x1350-v1.jpg.import
docs/marketing/campaign-01/visuals/mayor-simulator-community-4x5-v1.png
docs/marketing/campaign-01/visuals/mayor-simulator-community-4x5-v1.png.import
docs/marketing/campaign-01/visuals/mayor-simulator-itch-cover-630x500-v1.jpg
docs/marketing/campaign-01/visuals/mayor-simulator-itch-cover-630x500-v1.jpg.import
docs/marketing/campaign-01/visuals/mayor-simulator-itch-cover-source-v1.png
docs/marketing/campaign-01/visuals/mayor-simulator-itch-cover-source-v1.png.import
docs/marketing/campaign-01/visuals/mayor-simulator-mvp-alpha-hero-16x9-v1.png
docs/marketing/campaign-01/visuals/mayor-simulator-mvp-alpha-hero-16x9-v1.png.import
docs/marketing/campaign-01/visuals/mayor-simulator-mvp-alpha-hero-1920x1080-v1.jpg
docs/marketing/campaign-01/visuals/mayor-simulator-mvp-alpha-hero-1920x1080-v1.jpg.import
docs/marketing/campaign-01/visuals/mayor-simulator-promise-1080x1920-v1.jpg
docs/marketing/campaign-01/visuals/mayor-simulator-promise-1080x1920-v1.jpg.import
docs/marketing/campaign-01/visuals/mayor-simulator-promise-9x16-v1.png
docs/marketing/campaign-01/visuals/mayor-simulator-promise-9x16-v1.png.import
skills/mayor-simulator-sdk/agents/openai.yaml
tests/integration/locale_switch_state_preservation_test.gd.uid
tests/integration/map_zoom_all_layers_acceptance_test.gd.uid
tests/integration/public_affairs_reload_lifecycle_test.gd.uid
tests/integration/public_service_lifecycle_test.gd.uid
tests/integration/terrain_flatten_lifecycle_test.gd.uid
tests/integration/transport_all_mode_lifecycle_contract_test.gd.uid
tests/ui/public_affairs_status_lifecycle_test.gd.uid
專案移交_2026-08-02/.gdignore
莉拉，柳樹村的花店員.png
```

## OWNERSHIP_MATRIX overlaps

The three columns are `65ceea3 | 682b0d1 | e443aeb` blob IDs. Only
`assertion_matrix` and `capture_ui_readability` contain courtroom-semantic
hunks. The seven UID entries are collateral; subsequent UI/terrain/schema work
did not alter any of these nine paths.

```text
tests/assertion_matrix.json|f51f71a2c1bb8b899b5c02b9c4977f05068ac49e|991d9dae2751ae0e809b445701da646b07cf6228|991d9dae2751ae0e809b445701da646b07cf6228
tests/ui/capture_ui_readability.gd|6d5fccccbbe059c3ac0f22a5f62b53da1e5ae863|e3669251c6488d0f449b9ddbd69f612c2cfea6c9|e3669251c6488d0f449b9ddbd69f612c2cfea6c9
tests/integration/locale_switch_state_preservation_test.gd.uid|ABSENT|4509eca64b2d4fae793db00e359218926df7dcf5|4509eca64b2d4fae793db00e359218926df7dcf5
tests/integration/map_zoom_all_layers_acceptance_test.gd.uid|ABSENT|794d69a7b2c5180b988ba65df8edf6a451fec0fe|794d69a7b2c5180b988ba65df8edf6a451fec0fe
tests/integration/public_affairs_reload_lifecycle_test.gd.uid|ABSENT|7c9c6264b0fe2001117553a3fb2f1dbcb229858e|7c9c6264b0fe2001117553a3fb2f1dbcb229858e
tests/integration/public_service_lifecycle_test.gd.uid|ABSENT|54df7a8fde89c562a98ffcc0af43edc507683001|54df7a8fde89c562a98ffcc0af43edc507683001
tests/integration/terrain_flatten_lifecycle_test.gd.uid|ABSENT|00ebca11f1aa031577c8f3756412d54eae747be7|00ebca11f1aa031577c8f3756412d54eae747be7
tests/integration/transport_all_mode_lifecycle_contract_test.gd.uid|ABSENT|6df05d6cb77d60b282cac759c23587393df0a319|6df05d6cb77d60b282cac759c23587393df0a319
tests/ui/public_affairs_status_lifecycle_test.gd.uid|ABSENT|1cdb2ad6d054a3cb0247de6aa5b7f997f48a629e|1cdb2ad6d054a3cb0247de6aa5b7f997f48a629e
```

## Current disposition and image proof

26/27 court-owned paths are unchanged from `682b0d1` to `e443aeb`.
`ui/governance/courtroom_stage.gd` was safely superseded by `efb81ed`:
the ResourceLoader correction loads courtroom textures as imported resources.

For each PNG, raw materialized content, `682b0d1`, and `e443aeb` agree:

```text
court_clerk.png|1218172|A261E99D7986ABB3B2CAE25AF3EAF76425DF09EEDBD20F5D46B7519DE84CC22E
courtroom_interior.png|1951308|22FA29B0D49C3162E3FB6A25254DE010216EF78FDE2CF73EC34D5564FB4CC04E
defense_table.png|1371173|540F8E1D76F39E9DA6802938CB853621FF276015CC09992360A2486AB11042D8
judicial_panel.png|1557448|162A023FFF54F56932EA401867278F66D2907CB62AA1E9296DA19913C91C88A4
```

## REQ-GOAL-06 traceability and evidence boundary

The integrated slice covers multi-case, roles/seating, dates/phases, defense,
light/dark, five-language localization, governance/save, and a visible
courtroom. Existing current evidence is 67/67 and canonical UI is 37/37 at
`e443aeb`; this docs-only batch cites them and did not rerun either set.

## Reverification

```powershell
git diff --name-only 65ceea3 682b0d1
git diff --name-only 65ceea3 682b0d1 | Measure-Object
git diff --name-only 682b0d1 e443aeb -- ui/governance/courtroom_stage.gd
Get-FileHash -Algorithm SHA256 assets/images/ui/courtroom_v1/court_clerk.png
```
