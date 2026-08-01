# 市長模擬器專案導覽

本目錄是整理後的唯一文件入口。若要快速了解專案，先看本頁；若要查單一檔案，請看
[專案檔案用途索引](project-organization/FILE_INDEX.md)；若要追查搬移前後位置，請看
[遷移對照表](project-organization/MIGRATION_MAP.md)；若要確認整理後是否仍可運作，請看
[驗證報告](project-organization/VALIDATION_REPORT.md)；若要查看數據視覺化 UI 的前後比較與測試結果，請看
[UI 視覺化報告](project-organization/UI_VISUALIZATION_REPORT.md)；圖片主導版本請看
[圖片主導 UI 報告](project-organization/PICTURE_FIRST_UI_REPORT.md)。
也可直接看
[資料夾分類清單](project-organization/FOLDER_CLASSIFICATION.md)。
司法與監察拆分、辯護流程及最新畫面請看
[司法與監察獨立 UI 報告](project-organization/JUDICIAL_OVERSIGHT_UI_REPORT.md)。

## 目錄樹

```text
專案根目錄
├─ project.godot / export_presets.cfg   Godot 根設定
├─ scenes/                              場景入口
├─ data/
│  ├─ catalogs/                         建築、政策與內容目錄
│  ├─ schemas/                          資料結構與平衡參數
│  └─ databases/governance/             下議院、司法與監察 JSON 主資料
├─ scripts/
│  ├─ app/                              遊戲入口與跨系統協調
│  ├─ core/                             模擬、事件、存檔與狀態核心
│  ├─ systems/                          城建、治理、人口等共用系統
│  ├─ world/                            城市場景與 NPC 顯示元件
│  └─ rendering/                        畫面著色器
├─ systems/governance/                  可獨立驗證的議會／司法模組
├─ ui/                                  遊戲畫面與互動面板
├─ ux/                                  體驗與美編規格
├─ assets/                              執行圖片、概念圖、參考圖與封存包
├─ tests/                               單元、整合與 UI 擷取測試
├─ artifacts/                           測試紀錄與畫面產物
├─ docs/                                設計、開發、系統與整理文件
└─ backups/                             本次整理前的安全備份
```

## 系統與檔案入口

| 系統 | 程式入口 | 資料入口 | 介面／文件 |
| --- | --- | --- | --- |
| 應用程式 | `scripts/app/main.gd` | `project.godot` | `ui/shell/` |
| 模擬核心 | `scripts/core/game_session.gd` | `scripts/core/city_state.gd` | `docs/development/` |
| 城建 | `scripts/systems/city/construction_system.gd` | `data/catalogs/buildings.gd` | 主畫面建築頁 |
| 建築耐久 | `scripts/systems/city/durability_system.gd` | `data/schemas/building_definition.gd` | 主畫面建築資料頁 |
| 治理 | `scripts/systems/governance/governance_system.gd` | `data/catalogs/policies.gd` | `ui/shell/vertical_slice_panel.gd` |
| 下議院 | `systems/governance/lower-council/` | `data/databases/governance/lower-council/` | `docs/systems/governance/lower_council.md` |
| 司法與監察 | `systems/governance/justice-oversight/` | `data/databases/governance/justice-oversight/` | `ui/governance/justice_oversight_panel.gd` |
| 人口與 NPC | `scripts/systems/population/population_system.gd` | 程式內產生的 NPC 狀態 | `scripts/world/npc_actor.gd` |
| 世界畫面 | `scripts/world/` | `assets/images/world/` | `scenes/Main.tscn` |

## 分類邊界

- `data/databases/` 只放可直接解析的 JSON 主資料；不要放測試紀錄或文件。
- `data/catalogs/` 是內容清單，`data/schemas/` 是欄位結構與規則，兩者不是人物資料庫。
- `ui/` 只負責玩家可見畫面；`ux/` 放體驗與美術規格，不放可執行程式。
- `assets/` 放遊戲可能載入或供設計參考的圖片；`artifacts/` 放測試跑完後產生的證據。
- `scripts/systems/` 是主遊戲共用系統；`systems/` 是具有自己資料、邏輯、文件與測試的自治模組。
- `.uid` 與 `.import` 是 Godot 配套檔，必須和同名來源檔一起搬移，不可單獨整理。

## 安全與維護

- 整理前快照：`backups/mayor-simulator-pre-organization-20260722.zip`。
- `.godot/` 是引擎快取，可重新產生，不應手動分類其中檔案。
- `.tmp.driveupload/`、`.tmp.drivedownload/` 是同步工具暫存目錄，整理時不更動。
- 本次整理只更換檔案位置與引用路徑，沒有改變遊戲規則、平衡數值或案件資料。
