# Full integration worktree intake (2026-09-02)

This ledger seals the source inventory for `codex/full-integration-20260902`.
It records every registered game worktree and the two independently discovered
SDK worktrees without modifying, cleaning, stashing, or committing their WIP.

## Integration anchor

- Target branch: `codex/full-integration-20260902`
- Target base: `f2663928fc0d33f27b377f2705e84b1e9be90d1f`
- Target base tree: `6f1b882508c705c3f0ae0233e9d8cd174f8d02aa`
- Rollback branch: `codex/backup-square-grid-footprint-transport-20260902`
- Pre-feature rollback: `codex/backup-pre-square-grid-20260901@cfbb4a6d00c87f2d739257d4c2fa8e6bf33fb37d`
- Intake rule: integrate live product behavior and contracts, not a mechanical
  union of every branch or dirty file.

## Game worktrees

| Worktree | Branch | HEAD / tree | State | Relation to target | Intake |
|---|---|---|---|---|---|
| `30_core` | `codex/linux-ci-alpha3-20260811` | `f991f21 / bd12628c` | clean | diverged, base `cfbb4a6` | semantic review only |
| `antigravity-ambiguity-pilot-01` | `codex/antigravity-ambiguity-pilot-01` | `cfbb4a6 / 881b21f8` | 1 modified | ancestor | preserve test intent; do not apply patch |
| `antigravity-bootstrap-pilot-01` | `codex/antigravity-bootstrap-pilot-01` | `cfbb4a6 / 881b21f8` | 1 modified | ancestor | preserve test intent; do not apply patch |
| `antigravity-tutorial-pilot-01` | `codex/antigravity-tutorial-pilot-01` | `cfbb4a6 / 881b21f8` | 1 modified | ancestor | preserve test intent; do not apply patch |
| `antigravity-w2-pilot-02` | `codex/antigravity-w2-pilot-02` | `cfbb4a6 / 881b21f8` | 1 modified | ancestor | preserve test intent; do not apply patch |
| `antigravity-write-pilot-01` | `codex/antigravity-write-pilot-01` | `cfbb4a6 / 881b21f8` | 1 modified | ancestor | preserve test intent; do not apply patch |
| `b4-1-production-codec` | `codex/b4-1-production-codec` | `718ce70c / d933c2e6` | clean | diverged, base `cfbb4a6` | excluded unless profiling proves a save bottleneck |
| `b4-2a-generation-store` | `codex/b4-2a-generation-store` | `f4c05780 / 01d3b28f` | clean | diverged, base `cfbb4a6` | excluded unless profiling and migration review justify it |
| `b4-schema-authority` | `codex/b4-schema-authority` | `fd65db2f / 46f4133b` | clean | ancestor | already absorbed |
| `b5-backdrop-terrain` | `codex/b5-backdrop-terrain` | `162fc0dc / 0248bd4f` | clean | ancestor | already absorbed |
| `b6-3-save-load` | `codex/b6-3-save-load` | `12ea078b / 4dd34d78` | clean | diverged, base `cfbb4a6` | prototype only; do not merge |
| `b9-court-image-loader` | `codex/b9-court-image-loader` | `efb81ed2 / 0bfba79e` | clean | ancestor | already absorbed |
| `b9-court-ledger-close` | `codex/b9-court-ledger-close` | `10c1d902 / 239f3c78` | clean | ancestor | already absorbed |
| `c3-schema8-layout3` | `codex/c3-schema8-layout3` | `b138b636 / 63d84593` | clean | ancestor | already absorbed |
| `control-plane-skill-routing` | `codex/control-plane-skill-routing` | `cfbb4a6 / 881b21f8` | 1 modified, 1 untracked | ancestor | tool-only WIP; keep outside product integration |
| `full-integration-20260902` | `codex/full-integration-20260902` | `f2663928 / 6f1b8825` | target edits | target | sole integration writer |
| `repository-governance-20260818` | `codex/repository-governance-20260818` | `61fa5028 / af4c7a9f` | clean | diverged, base `cfbb4a6` | inspect final audio/CI semantics; never merge wholesale |
| `restore-rar-required-sources` | `codex/restore-rar-required-sources` | `fc24bc70 / ae167c33` | clean | ancestor | already absorbed |
| `skill-sdk-1.2.1-contracts` | `codex/skill-sdk-1.2.1-contracts` | `7cf5311d / e21e9b04` | clean | ancestor | already absorbed |
| `square-grid-footprint-transport-20260901` | `codex/square-grid-footprint-transport-20260901` | `f2663928 / 6f1b8825` | clean | target-equivalent | fully absorbed as target base |
| `transport-visible-current` | `codex/transport-visible-current` | `dc66036e / cf498d7b` | clean | ancestor | already absorbed |
| `ui-polish-20260815` | `codex/ui-polish-20260815` | `cfbb4a6 / 881b21f8` | 31 modified, 2 untracked | ancestor WIP | semantic reconstruction only |
| `uiux-release-gaps` | `codex/uiux-release-gaps` | `e443aeb / bca7ae48` | 1 untracked | ancestor | committed behavior absorbed; preserve UID hash only |

## Dirty and untracked file hashes

Format: `status bytes sha256 path`. Hashes describe working files at intake
time and are not an instruction to stage them.

### Antigravity pilots

```text
antigravity-ambiguity-pilot-01
 M 26283 401553469D488F7B900035FCCA11634CB43B68F510DF3AD8F72495BF19C4584E tests/ui/multi_resolution_ui_acceptance_test.gd
antigravity-bootstrap-pilot-01
 M 26033 9077B1C3292EB6855C4EB7D12E1EBDCE065059623E1565FEEE98087B5DD12829 tests/ui/multi_resolution_ui_acceptance_test.gd
antigravity-tutorial-pilot-01
 M 25953 657842638BF356B1B071DAF22CEFD2985393439A1AF4D2B5C345F4990B589B30 tests/ui/multi_resolution_ui_acceptance_test.gd
antigravity-w2-pilot-02
 M 26495 0EC593D020DA37DD8B6437EDA5EDE68F7C0FFF94A001CFBC7F63BAB2B6E8FF20 tests/ui/multi_resolution_ui_acceptance_test.gd
antigravity-write-pilot-01
 M 27439 FE0693936ECBE3CC830178574D07AABDDFDECBA3F3EAADDA837ACC679EEF767E tests/ui/multi_resolution_ui_acceptance_test.gd
```

### Control-plane skill WIP

```text
 M 5509 9FFAEE241C759006CA8FF19C005A73631F504840FBD5E3AD3A261B3D5923DA6B skills/mayor-simulator-sdk/SKILL.md
?? 3575 EFC93BB87723644A1EF78CCEB8AAD6E839162AB34AFCF7E396B93DF33573D0EC skills/mayor-simulator-sdk/references/work-allocation.md
```

### UI-polish WIP

```text
 M 602 925B401038955A72587DF95E36131CEEE44D4CDD0A056A8B372F6F1565F712C1 .gitattributes
 M 1118 23EE5AC81F74662EBC293E4C5AE7170CC953A357D9B3312961D8BAD538CD4AD9 .gitignore
 M 94900 9C9ED19C34DAF5005295E9FBF44A33DAFD66AE97F6BD064DCEAB36B8D988548B data/localization/en.json
 M 102995 92EBAFA66F1345EF4078D8950003CCCD0AEB9F4C51ABDDAE4E89572B993F3B69 data/localization/ja.json
 M 98464 273701A4F997B8F1FA87E742EC36590BE3725F520A48670511F48581B80E6B27 data/localization/ko.json
 M 81929 DAD64D675C9199C1939F1F09DF420FEB2D43D8D0B293AE25B3640896F7254588 data/localization/zh_CN.json
 M 79809 0EBB67BD85B2DBABFCB1618028B81149676DC053CDEDDEC0C3AD68BEB8CA0320 data/localization/zh_TW.json
 M 268767 2B0D9107721EBE9B790FCF15D160E84C063BEE40EE21CFD4C5837B4A3FF34F21 scripts/app/main.gd
 M 21252 EC982ED4661FBF61EDF133A5A3281882395555289A4C564B3BEFCD8A8D0A66F4 tests/integration/localization_test.gd
 M 58957 B6087C29A06F1DA633E0371953D50FF7319C2DFDC2463DA645D78CD3FE5B217E tests/integration/main_integration_test.gd
 M 11291 8FF0CD5A45217D49407F6EBFAE5157F94065D3805B1F8259A4F1366CBB3AD04A tests/integration/progressive_disclosure_test.gd
 M 88721 5BDA3A6483625CEED724189F40CD7E751DA5CE5C3606D9CB66C985391698520E tests/ui/capture_ui_readability.gd
 M 13103 89A01C7B93AD4F33F57998FA344F8CE15E591651136C00B18BD58E4FF27B77EA tests/ui/city_data_dashboard_test.gd
 M 4955 E8345DF0353356E015B13B1C4298E856F95629B9F6F103F8A5955696EB13F3ED tests/ui/courtroom_visual_acceptance_test.gd
 M 7337 9D082CBA05EB3CD4C0859C6104752AE85C0B76B04C118DD8DD16D45FA026AF5A tests/ui/governance_status_tabs_test.gd
 M 10595 D6EEED2F01E0A40A4D5ABCD23F8FC076878B076C7D6A5AA692354AD1CF8C48D4 tests/ui/justice_oversight_multi_case_test.gd
 M 33710 40986A2BF39AEBA5A3FA4AFE36CE2C658A0DFB953096C848D16A878651426E66 tests/ui/multi_resolution_ui_acceptance_test.gd
 M 6007 F622635BCA7C6EDBF628AB3DC8F45EE3D5FB9775D243FE7E3A1C7D9E832323C4 tests/ui/public_affairs_status_lifecycle_test.gd
 M 10710 CE89631F81059529AF9E586B819F18E923EFC60FEE198D7B4DC9046808AC9882 tests/ui/settings_overlay_style_test.gd
 M 12158 00F1B52C0ED36E568E1302CA5671F82411DDA6204D79C1D24654DC9CBDF9F1C0 tests/ui/transport_planning_panel_test.gd
 M 5530 43232C5F706D3B6EEBE34C15E00A4853E9DFA91602331190E4355E735AD6FD9C tests/ui/visual_safety_regression_test.gd
 M 12032 8C44B46A5891A5CC833ED8FE21ED57FACFB2268DBEAD08E89FFD5FC7A85CEA82 ui/components/benchmark_delta_chart.gd
 M 5343 4FBF0163E1B79AAF4672CAA85D9E50325439637408DBCD27ABD0D9593D17C4B1 ui/components/progressive_choice_pager.gd
 M 7451 3BFCB8811652CB8CEB1E07C023BA00B154FA00C52061F95FEBB8B13C0F8C1A02 ui/governance/courtroom_stage.gd
 M 27449 668E13F0D5B9E33E69E4B0D1DAB0B987554DBDFF60526EE69F278C070EC27983 ui/governance/justice_oversight_panel.gd
 M 35614 B538CC659F7120CF98C8A29DD7348DA6E4B4CDB7759EA4D98097E60957026F77 ui/shell/city_data_dashboard.gd
 M 23982 7120D90CE6CB6B60605E098144E0D0F309A0702ED009E0065E286588FA0AC214 ui/shell/municipal_overlay.gd
 M 10894 69B19F256398DB2024472D4857560D65F6076B4991C855E4504824B3781F3740 ui/shell/public_affairs_panel.gd
 M 17660 84382533A791B85B1CCE1922B9CA6D6BBB9146224EE8DE64BDC2693190D0F166 ui/shell/settings_overlay.gd
 M 34152 736A09E61BFC0A4F9EC8940918F1B9CB94EFF8950DF5FC88C6E8DAC6D36CCA1B ui/shell/transport_planning_panel.gd
 M 35706 8EACC63228E7C122089263C6DA6EE10A6C6C02346E562073E0531FFB6AB26FC3 ui/shell/vertical_slice_panel.gd
?? 7320 EE14A4E94048AAF101610477A5480688DC23E7663A9B27137BF2DC8AE5B8F34E ui/governance/governance_dialogue_flow.gd
?? 20 7253542B6F5D1303270846DAA10DB023B202A96A702705265920FB11A1907DF1 ui/governance/governance_dialogue_flow.gd.uid
```

### UIUX release gap and independent SDK WIP

```text
uiux-release-gaps
?? 20 6783FE1948F7B5A7B76EDB83A79767A5EDF78B540918E3435DD7CEA655464044 tests/manual/map_zoom_pan_visible_acceptance.gd.uid

C:\Users\USER\遊戲\sdk (main@619a50a6 / tree 2e19e3a7)
 M 27648 FFD03C1D3C70E98B5DCDD152D26E05CD445BB8773816901E24587F9831561722 mayor_sdk.py

C:\Users\USER\遊戲\MayorSimulator_Authoritative_2026-08-02\sdk
detached@956f0414 / tree 61ed3cf0 / clean
```

## Acceptance consequence

- The canonical assertion inventory must include every on-disk `*_test.gd`.
- Dirty source worktrees remain authoritative preservation sources only; their
  files are never cleaned or staged by this integration.
- UI-polish behavior is reimplemented against current square-grid, footprint,
  transport-session, save-schema, and navigation authority.
- Population generation/save-codec prototypes remain excluded until current,
  repeatable profiling proves they solve a measured bottleneck without save
  compatibility or play-experience regression.
